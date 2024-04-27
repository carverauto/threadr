package middleware

import (
	firebase "firebase.google.com/go"
	"github.com/gofiber/fiber/v2"
	"log"
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

// SuperAdminAuthMiddleware checks to see if the user has the super admin claim set and is instance admin.
func SuperAdminAuthMiddleware(FirebaseApp *firebase.App) fiber.Handler {
	return func(c *fiber.Ctx) error {
		// get context from fiber.Ctx
		ctx := c.Context()

		authClient, err := FirebaseApp.Auth(ctx)
		if err != nil {
			log.Println("Failed to initialize Firebase Auth client:", err)
			return c.Status(fiber.StatusInternalServerError).SendString("Internal Server Error")
		}

		idToken := c.Get("Authorization")
		token, err := authClient.VerifyIDToken(ctx, idToken)
		if err != nil {
			log.Printf("Token verification failed: %v", err)
			return c.Status(fiber.StatusUnauthorized).SendString("Unauthorized access - Invalid token")
		}

		claims := token.Claims
		expectedInstanceId := c.Params("instance") // Retrieve instance ID from the URL parameter

		role, hasRole := claims["role"].(string)
		instanceId, hasInstanceId := claims["InstanceId"].(string)
		if !hasRole || role != "super" {
			log.Printf("Access denied: user role '%v' is not 'admin'", role)
			return c.Status(fiber.StatusForbidden).SendString("Access denied - You must be an admin")
		}
		if !hasInstanceId || instanceId != expectedInstanceId {
			log.Printf("Access denied: user's instanceID '%v' does not match expected '%v'", instanceId, expectedInstanceId)
			return c.Status(fiber.StatusForbidden).SendString("Access denied - Invalid instance access")
		}

		return c.Next()
	}
}
