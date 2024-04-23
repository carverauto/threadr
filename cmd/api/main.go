package main

import (
	"context"
	"fmt"
	"github.com/carverauto/threadr/pkg/api/firebase"
	"github.com/carverauto/threadr/pkg/api/routes"
	"github.com/gofiber/fiber/v2"
	"github.com/joho/godotenv"
	gofiberfirebaseauth "github.com/sacsand/gofiber-firebaseauth"
	"log"
	"time"
)

func main() {
	err := godotenv.Load()
	if err != nil {
		log.Println("Error loading .env file")
	}

	app := fiber.New(
		fiber.Config{
			EnablePrintRoutes: true,
		},
	)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	FirebaseApp, err := firebase.SetupFirebaseApp(ctx)
	if err != nil {
		log.Println("Error initializing Firebase App:", err)
		return
	}

	secure := app.Group("/secure")
	secure.Use(gofiberfirebaseauth.New(gofiberfirebaseauth.Config{
		FirebaseApp: FirebaseApp,
		ErrorHandler: func(ctx *fiber.Ctx, err error) error {
			log.Println("Error:", err)
			errMsg := fmt.Sprintf("Unauthorized: %s", err.Error())
			return ctx.Status(fiber.StatusUnauthorized).SendString(errMsg)
		},
	}))

	routes.SetupSecureRoutes(secure, FirebaseApp)
	routes.SetupRoutes(app, FirebaseApp)

	fErr := app.Listen(":3001")
	if fErr != nil {
		log.Println("Error starting the server:", fErr)
		return
	}
}
