package middleware

import (
	"context"
	firebase "firebase.google.com/go"
	"github.com/gofiber/fiber/v2"
	"log"
)

// RoleTenantMiddleware is a middleware that checks if the user is an admin and belongs to the expected tenant
func RoleTenantMiddleware(FirebaseApp *firebase.App) fiber.Handler {
	return func(c *fiber.Ctx) error {
		authClient, err := FirebaseApp.Auth(context.Background())
		if err != nil {
			log.Println("Failed to initialize Firebase Auth client:", err)
			return c.Status(fiber.StatusInternalServerError).SendString("Internal Server Error")
		}

		idToken := c.Get("Authorization")
		token, err := authClient.VerifyIDToken(context.Background(), idToken)
		if err != nil {
			return c.Status(fiber.StatusUnauthorized).SendString("Unauthorized access")
		}

		claims := token.Claims
		if role, ok := claims["role"].(string); !ok || role != "admin" {
			return c.Status(fiber.StatusForbidden).SendString("Access denied")
		}
		if tenantId, ok := claims["tenantId"].(string); !ok || tenantId != "expectedTenantId" {
			return c.Status(fiber.StatusForbidden).SendString("Access denied for this tenant")
		}

		c.Locals("user", claims)
		return c.Next()
	}
}
