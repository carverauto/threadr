package middleware

import (
	"context"
	firebase "firebase.google.com/go"
	"github.com/gofiber/fiber/v2"
	"log"
)

// RoleTenantMiddleware checks if the user is an admin and if they belong to the tenant specified in the URL.
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
			log.Printf("Token verification failed: %v", err)
			return c.Status(fiber.StatusUnauthorized).SendString("Unauthorized access - Invalid token")
		}

		claims := token.Claims
		expectedTenantId := c.Params("tenant") // Retrieve tenant ID from the URL parameter

		role, hasRole := claims["role"].(string)
		tenantId, hasTenantId := claims["tenantId"].(string)
		if !hasRole || role != "admin" {
			log.Printf("Access denied: user role '%v' is not 'admin'", role)
			return c.Status(fiber.StatusForbidden).SendString("Access denied - You must be an admin")
		}
		if !hasTenantId || tenantId != expectedTenantId {
			log.Printf("Access denied: user's tenantId '%v' does not match expected '%v'", tenantId, expectedTenantId)
			return c.Status(fiber.StatusForbidden).SendString("Access denied - Invalid tenant access")
		}

		return c.Next()
	}
}
