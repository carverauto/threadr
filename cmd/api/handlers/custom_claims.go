package handlers

import (
	"context"
	firebase "firebase.google.com/go"
	"github.com/gofiber/fiber/v2"
)

// SetCustomClaimsHandler sets custom claims for a user
func SetCustomClaimsHandler(app *firebase.App) fiber.Handler {
	return func(c *fiber.Ctx) error {
		type RequestBody struct {
			UserID string                 `json:"userId"`
			Claims map[string]interface{} `json:"claims"`
		}

		var body RequestBody
		if err := c.BodyParser(&body); err != nil {
			return c.Status(fiber.StatusBadRequest).SendString("Bad request")
		}

		ctx := context.Background()
		authClient, err := app.Auth(ctx)
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).SendString("Failed to get Auth client")
		}

		// Set custom user claims
		err = authClient.SetCustomUserClaims(ctx, body.UserID, body.Claims)
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).SendString("Failed to set custom claims")
		}

		return c.SendString("Custom claims updated successfully")
	}
}
