package handlers

import (
	"context"
	firebase "firebase.google.com/go"
	"fmt"
	"github.com/gofiber/fiber/v2"
	"log"
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

// GetCustomClaimsHandler gets custom claims for a user
func GetCustomClaimsHandler(app *firebase.App) fiber.Handler {
	return func(c *fiber.Ctx) error {
		userId := c.Params("userId") // Get userId from URL params

		ctx := c.Context()

		authClient, err := app.Auth(ctx)
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).SendString("Failed to get Auth client")
		}

		// Get custom user claims
		// Lookup the user associated with the specified uid.
		fmt.Println("Looking up user:", userId)
		user, err := authClient.GetUser(ctx, userId)
		if err != nil {
			log.Fatal(err)
		}
		// The claims can be accessed on the user record.
		if admin, ok := user.CustomClaims["admin"]; ok {
			if admin.(bool) {
				log.Println(admin)
			}
		}

		return c.JSON(user)
	}
}
