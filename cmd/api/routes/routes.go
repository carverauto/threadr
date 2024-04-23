package routes

import (
	firebase "firebase.google.com/go"
	"github.com/gofiber/fiber/v2"
	"os"
	"whatsapp-fiber/handlers"
	"whatsapp-fiber/middleware"
)

// SetupRoutes sets up the routes for the application
func SetupRoutes(app *fiber.App, FirebaseApp *firebase.App) {
	app.Get("/", func(c *fiber.Ctx) error {
		return c.SendString("Hello, World 👋!")
	})

	// Protected route with role and tenant check
	app.Get("/secure", middleware.RoleTenantMiddleware(FirebaseApp), func(c *fiber.Ctx) error {
		userClaims := c.Locals("user").(map[string]interface{})
		return c.SendString("Welcome Admin, Tenant ID: " + userClaims["tenantId"].(string))
	})

	// Admin route to set custom claims
	app.Post("/admin/set-claims",
		middleware.ApiKeyMiddleware(os.Getenv("ADMIN_API_KEY")),
		handlers.SetCustomClaimsHandler(FirebaseApp))
}
