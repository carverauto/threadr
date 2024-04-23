package main

import (
	"context"
	"github.com/carverauto/threadr/cmd/api/firebase"
	"github.com/carverauto/threadr/cmd/api/routes"
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

	app.Use(gofiberfirebaseauth.New(gofiberfirebaseauth.Config{
		FirebaseApp: FirebaseApp,
		IgnoreUrls:  []string{"GET::/", "POST::/admin/set-claims"},
	}))

	routes.SetupRoutes(app, FirebaseApp)

	fErr := app.Listen(":3001")
	if fErr != nil {
		log.Println("Error starting the server:", fErr)
		return
	}
}
