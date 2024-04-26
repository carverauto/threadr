package middleware

import (
	"github.com/gofiber/fiber/v2"
	"os"
)

// ApiKeyMiddleware authenticates requests using a predefined API key.
func ApiKeyMiddleware() fiber.Handler {
	apiKey := os.Getenv("ADMIN_API_KEY") // Load the API key once when the middleware is initialized.
	return func(c *fiber.Ctx) error {
		if c.Get("X-API-Key") != apiKey {
			return c.Status(fiber.StatusUnauthorized).SendString("Invalid API key")
		}
		return c.Next()
	}
}
