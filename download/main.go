package main

import (
    "database/sql"
    "errors"
    "fmt"
    "io"
    "log"
    "mime/multipart"
    "net/http"
    "net/url"
    "os"
    "path/filepath"
    "strings"
    "time"

    "github.com/gin-gonic/gin"
    _ "github.com/lib/pq"
    _ "modernc.org/sqlite"
)

var authToken = getenvDefault("API_TOKEN", "token")

func authMiddleware(c *gin.Context) {
	if c.GetHeader("X-Auth") != authToken {
		c.AbortWithStatus(http.StatusUnauthorized)
		return
	}
	c.Next()
}

type Item struct {
    ID         int       `json:"id"`
    Title      string    `json:"title"`
    Status     string    `json:"status"`
    Path       string    `json:"path"`
    SpritePath string    `json:"spritePath"`
    CreatedAt  time.Time `json:"createdAt"`
}

type MagnetResult struct {
	Title  string `json:"title"`
	Magnet string `json:"magnet"`
}

// External Bitmagnet DB (optional) and local app DB
var bitmagnetDB *sql.DB
var appDB *sql.DB

type Config struct {
    DownloadDir string `json:"downloadDir"`
    Port        int    `json:"port"`
    WorkerAddr  string `json:"workerAddr"`
}

var cfg = Config{DownloadDir: getenvDefault("DOWNLOAD_ROOT", "/downloads"), Port: 28000, WorkerAddr: getenvDefault("WORKER_ADDR", "http://localhost:9001")}

var previewRoot = getenvDefault("PREVIEW_ROOT", "/previews")

func getenvDefault(k, v string) string {
    if val := os.Getenv(k); val != "" {
        return val
    }
    return v
}

func mustInitSQLite() {
    dbPath := getenvDefault("DB_PATH", "./seedbox.db")
    var err error
    appDB, err = sql.Open("sqlite", dbPath)
    if err != nil {
        log.Fatalf("open sqlite failed: %v", err)
    }
    // conservative busy timeout
    appDB.Exec("PRAGMA busy_timeout = 3000;")
    _, err = appDB.Exec(`
        CREATE TABLE IF NOT EXISTS items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            status TEXT NOT NULL,
            path TEXT NOT NULL,
            sprite_path TEXT,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        CREATE INDEX IF NOT EXISTS idx_items_status ON items(status);
    `)
    if err != nil {
        log.Fatalf("migrate sqlite failed: %v", err)
    }
}

func setupRouter() *gin.Engine {
    if appDB == nil {
        mustInitSQLite()
    }
    r := gin.Default()
    api := r.Group("/")
    api.Use(authMiddleware)
    api.GET("/items", handleListItems)
    api.POST("/tasks/fetch", handleFetchTask)
    api.PATCH("/items/:id", handlePatchItem)
    api.DELETE("/items/:id", handleDeleteItem)
    api.POST("/jobs/next", handleJobsNext)
    api.POST("/jobs/:id/done", handleJobsDone)
    api.GET("/config", func(c *gin.Context) {
        c.JSON(http.StatusOK, cfg)
    })
    api.POST("/config", func(c *gin.Context) {
        if err := c.BindJSON(&cfg); err != nil {
            c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
            return
        }
        c.Status(http.StatusOK)
    })
    api.GET("/search", func(c *gin.Context) {
        q := c.Query("q")
        if q == "" {
            c.JSON(http.StatusBadRequest, gin.H{"error": "missing q"})
            return
        }
        if bitmagnetDB == nil {
            c.JSON(http.StatusInternalServerError, gin.H{"error": "db not configured"})
            return
        }
        rows, err := bitmagnetDB.Query(`SELECT encode(info_hash,'hex') as hash, name FROM torrents WHERE name ILIKE '%' || $1 || '%' LIMIT 20`, q)
        if err != nil {
            c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
            return
        }
        defer rows.Close()
        var results []MagnetResult
        for rows.Next() {
            var hash, name string
            if err := rows.Scan(&hash, &name); err != nil {
                c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
                return
            }
            magnet := fmt.Sprintf("magnet:?xt=urn:btih:%s&dn=%s", hash, url.QueryEscape(name))
            results = append(results, MagnetResult{Title: name, Magnet: magnet})
        }
        c.JSON(http.StatusOK, results)
    })
    r.Static("/admin", "../frontend")
    return r
}

func main() {
    var err error
    host := os.Getenv("BITMAGNET_DB_HOST")
    port := os.Getenv("BITMAGNET_DB_PORT")
    user := os.Getenv("BITMAGNET_DB_USER")
    pass := os.Getenv("BITMAGNET_DB_PASS")
    name := os.Getenv("BITMAGNET_DB_NAME")
    if name == "" {
        name = "bitmagnet"
    }
    if host != "" && port != "" && user != "" {
        dsn := fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=disable", user, pass, host, port, name)
        bitmagnetDB, err = sql.Open("postgres", dsn)
        if err != nil {
            log.Printf("db open failed: %v", err)
        }
    }
    mustInitSQLite()
    setupRouter().Run(":28000")
}

// Handlers
func handleListItems(c *gin.Context) {
    rows, err := appDB.Query("SELECT id, title, status, path, IFNULL(sprite_path,'') as sprite_path, created_at FROM items ORDER BY created_at DESC")
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    defer rows.Close()
    items := make([]Item, 0)
    for rows.Next() {
        var it Item
        var sprite sql.NullString
        if err := rows.Scan(&it.ID, &it.Title, &it.Status, &it.Path, &sprite, &it.CreatedAt); err != nil {
            c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
            return
        }
        if sprite.Valid {
            it.SpritePath = sprite.String
        }
        items = append(items, it)
    }
    c.JSON(http.StatusOK, items)
}

type fetchReq struct {
    URI     string `json:"uri"`
    InfoHash string `json:"infohash"`
    Path    string `json:"path"`
    Title   string `json:"title"`
}

func handleFetchTask(c *gin.Context) {
    var req fetchReq
    if err := c.BindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }
    // Minimal implementation: allow registering an already-downloaded file path
    if strings.TrimSpace(req.Path) == "" {
        c.JSON(http.StatusBadRequest, gin.H{"error": "path required for now"})
        return
    }
    title := req.Title
    if title == "" {
        title = filepath.Base(req.Path)
    }
    status := "downloaded" // available for preview generation
    res, err := appDB.Exec("INSERT INTO items(title, status, path) VALUES(?,?,?)", title, status, req.Path)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    id, _ := res.LastInsertId()
    c.JSON(http.StatusOK, gin.H{"id": id})
}

func handlePatchItem(c *gin.Context) {
    id := c.Param("id")
    var payload map[string]any
    if err := c.BindJSON(&payload); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
        return
    }
    if title, ok := payload["title"].(string); ok {
        if _, err := appDB.Exec("UPDATE items SET title = ? WHERE id = ?", title, id); err != nil {
            c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
            return
        }
    }
    if status, ok := payload["status"].(string); ok {
        if _, err := appDB.Exec("UPDATE items SET status = ? WHERE id = ?", status, id); err != nil {
            c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
            return
        }
    }
    c.Status(http.StatusOK)
}

func handleDeleteItem(c *gin.Context) {
    id := c.Param("id")
    // Best-effort delete; in real impl also remove files
    if _, err := appDB.Exec("DELETE FROM items WHERE id = ?", id); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    c.Status(http.StatusOK)
}

func handleJobsNext(c *gin.Context) {
    tx, err := appDB.Begin()
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    defer tx.Rollback()
    // Find next item without sprite, not processing
    row := tx.QueryRow(`SELECT id, path FROM items WHERE (status = 'downloaded' OR status = 'pending' OR status = 'pending-preview') AND (sprite_path IS NULL OR sprite_path = '') ORDER BY created_at ASC LIMIT 1`)
    var id int
    var path string
    if err := row.Scan(&id, &path); err != nil {
        if errors.Is(err, sql.ErrNoRows) {
            c.Status(http.StatusNoContent)
            return
        }
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    if _, err := tx.Exec("UPDATE items SET status = 'processing' WHERE id = ?", id); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    if err := tx.Commit(); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    c.JSON(http.StatusOK, gin.H{"id": id, "path": path})
}

func handleJobsDone(c *gin.Context) {
    id := c.Param("id")
    file, header, err := c.Request.FormFile("sprite")
    if err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"error": "sprite file required"})
        return
    }
    defer file.Close()
    relPath, err := saveSpriteFile(id, file, header)
    if err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    if _, err := appDB.Exec("UPDATE items SET sprite_path = ?, status = 'ready' WHERE id = ?", relPath, id); err != nil {
        c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
        return
    }
    c.Status(http.StatusOK)
}

func saveSpriteFile(id string, file multipart.File, header *multipart.FileHeader) (string, error) {
    // Ensure directory
    dir := filepath.Join(previewRoot, "sprites")
    if err := os.MkdirAll(dir, 0o755); err != nil {
        return "", err
    }
    // Use id.jpg or preserve extension
    ext := filepath.Ext(header.Filename)
    if ext == "" {
        ext = ".jpg"
    }
    rel := filepath.Join("sprites", fmt.Sprintf("%s%s", id, ext))
    dstPath := filepath.Join(previewRoot, rel)
    out, err := os.Create(dstPath)
    if err != nil {
        return "", err
    }
    defer out.Close()
    if _, err := io.Copy(out, file); err != nil {
        return "", err
    }
    return rel, nil
}
