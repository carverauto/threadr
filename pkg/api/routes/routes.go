package routes

import (
	firebase "firebase.google.com/go"
	"github.com/carverauto/threadr/pkg/api/handlers"
	"github.com/carverauto/threadr/pkg/api/middleware"
	"github.com/gofiber/fiber/v2"
	"os"
)

// SetupRoutes sets up the routes for the application
func SetupRoutes(app *fiber.App, FirebaseApp *firebase.App) {
	app.Get("/", func(c *fiber.Ctx) error {
		return c.SendString("Hello, World 👋!")
	})

	// Admin route to set custom claims
	app.Post("/admin/set-claims",
		middleware.ApiKeyMiddleware(os.Getenv("ADMIN_API_KEY")),
		handlers.SetCustomClaimsHandler(FirebaseApp))

	// Admin route to get custom claims
	app.Get("/admin/get-claims/:userId",
		middleware.ApiKeyMiddleware(os.Getenv("ADMIN_API_KEY")),
		handlers.GetCustomClaimsHandler(FirebaseApp))
}

// SetupSecureRoutes sets up the secure routes for the application
func SetupSecureRoutes(secure fiber.Router, FirebaseApp *firebase.App) {
	// Protected route with role and tenant check
	secure.Get("/secure", middleware.RoleTenantMiddleware(FirebaseApp), func(c *fiber.Ctx) error {
		userClaims := c.Locals("user").(map[string]interface{})
		return c.SendString("Welcome Admin, Tenant ID: " + userClaims["tenantId"].(string))
	})
}
