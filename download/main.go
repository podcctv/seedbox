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

func setupRouter() *gin.Engine {
	r := gin.Default()
	r.Use(authMiddleware)
	r.GET("/items", func(c *gin.Context) {
		c.JSON(http.StatusOK, items)
	})
	r.POST("/tasks/fetch", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})
	r.PATCH("/items/:id", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})
	r.DELETE("/items/:id", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})
	r.POST("/jobs/next", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"id": 1, "path": "/tmp/video.mp4"})
	})
	r.POST("/jobs/:id/done", func(c *gin.Context) {
		c.Status(http.StatusOK)
	})
	return r
}

func main() {
	setupRouter().Run(":28000")
}
