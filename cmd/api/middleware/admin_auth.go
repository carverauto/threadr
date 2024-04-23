package middleware

import "github.com/gofiber/fiber/v2"

func ApiKeyMiddleware(requiredKey string) fiber.Handler {
	return func(c *fiber.Ctx) error {
		apiKey := c.Get("X-API-Key")
		if apiKey != requiredKey {
			return c.Status(fiber.StatusUnauthorized).SendString("Invalid API key")
		}
		return c.Next()
	}
}
