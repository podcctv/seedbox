package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"

	"github.com/gin-gonic/gin"
	_ "github.com/lib/pq"
)

const authToken = "token"

func authMiddleware(c *gin.Context) {
	if c.GetHeader("X-Auth") != authToken {
		c.AbortWithStatus(http.StatusUnauthorized)
		return
	}
	c.Next()
}

type Item struct {
	ID     int    `json:"id"`
	Title  string `json:"title"`
	Status string `json:"status"`
}

var items = []Item{{ID: 1, Title: "Sample", Status: "ready"}}

type MagnetResult struct {
	Title  string `json:"title"`
	Magnet string `json:"magnet"`
}

var db *sql.DB

type Config struct {
	DownloadDir string `json:"downloadDir"`
	Port        int    `json:"port"`
	WorkerAddr  string `json:"workerAddr"`
}

var cfg = Config{DownloadDir: "/downloads", Port: 28000, WorkerAddr: "http://localhost:9001"}

func setupRouter() *gin.Engine {
	r := gin.Default()
	api := r.Group("/")
	api.Use(authMiddleware)
	api.GET("/items", func(c *gin.Context) {
		c.JSON(http.StatusOK, items)
	})
	api.POST("/tasks/fetch", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})
	api.PATCH("/items/:id", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})
	api.DELETE("/items/:id", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})
	api.POST("/jobs/next", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"id": 1, "path": "/tmp/video.mp4"})
	})
	api.POST("/jobs/:id/done", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})
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
		if db == nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "db not configured"})
			return
		}
		rows, err := db.Query(`SELECT encode(info_hash,'hex') as hash, name FROM torrents WHERE name ILIKE '%' || $1 || '%' LIMIT 20`, q)
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
		db, err = sql.Open("postgres", dsn)
		if err != nil {
			log.Printf("db open failed: %v", err)
		}
	}
	setupRouter().Run(":28000")
}
