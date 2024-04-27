package middleware

import (
	"context"
	firebase "firebase.google.com/go"
	"github.com/gofiber/fiber/v2"
	"log"
)

// RoleInstanceMiddleware checks if the user is an admin and if they belong to the instance specified in the URL.
func RoleInstanceMiddleware(FirebaseApp *firebase.App) fiber.Handler {
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
		expectedInstanceId := c.Params("instance") // Retrieve instance ID from the URL parameter

		role, hasRole := claims["role"].(string)
		instanceId, hasInstanceId := claims["instanceId"].(string)
		if !hasRole || role != "admin" {
			log.Printf("Access denied: user role '%v' is not 'admin'", role)
			return c.Status(fiber.StatusForbidden).SendString("Access denied - You must be an admin")
		}
		if !hasInstanceId || instanceId != expectedInstanceId {
			log.Printf("Access denied: user's instanceId  '%v' does not match expected '%v'", instanceId, expectedInstanceId)
			return c.Status(fiber.StatusForbidden).SendString("Access denied - Invalid instance access")
		}

		return c.Next()
	}
}
