package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
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
	r.Static("/admin", "../frontend")
	return r
}

func main() {
	setupRouter().Run(":28000")
}
