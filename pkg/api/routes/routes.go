package routes

import (
	firebase "firebase.google.com/go"
	"github.com/carverauto/threadr/pkg/api/handlers"
	"github.com/carverauto/threadr/pkg/api/middleware"
	"github.com/gofiber/fiber/v2"
)

// SetupRoutes initializes the public and administrative routes.
func SetupRoutes(app *fiber.App, FirebaseApp *firebase.App) {
	app.Get("/", func(c *fiber.Ctx) error {
		return c.SendString("Hello, World 👋!")
	})

	admin := app.Group("/admin")
	admin.Post("/set-claims", middleware.ApiKeyMiddleware(), handlers.SetCustomClaimsHandler(FirebaseApp))
	admin.Get("/get-claims/:userId", middleware.ApiKeyMiddleware(), handlers.GetCustomClaimsHandler(FirebaseApp))
}

// SetupSecureRoutes initializes the routes that require role and tenant level security.
func SetupSecureRoutes(secure fiber.Router, FirebaseApp *firebase.App) {
	secure.Use(middleware.RoleInstanceMiddleware(FirebaseApp)) // Apply the middleware to all routes under /secure
	secure.Get("/:instance", func(c *fiber.Ctx) error {        // Instance-specific route
		userClaims := c.Locals("user").(map[string]interface{})
		return c.SendString("Welcome Admin, Instance ID: " + userClaims["instanceId"].(string))
	})
}
