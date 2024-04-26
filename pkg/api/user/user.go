package user

import (
	firebase "firebase.google.com/go"
	"github.com/gofiber/fiber/v2"
)

func CreateNewUser(app *firebase.App) fiber.Handler {
	return func(c *fiber.Ctx) error {
		return c.SendString("Create new user")
	}
}

func CreateNewTenant(app *firebase.App) fiber.Handler {
	return func(c *fiber.Ctx) error {
		return c.SendString("Create new tenant")
	}
}
