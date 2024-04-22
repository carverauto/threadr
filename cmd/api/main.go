package main

import (
	"context"
	firebase "firebase.google.com/go"
	"github.com/gofiber/fiber/v2"
	"github.com/joho/godotenv"
	gofiberfirebaseauth "github.com/sacsand/gofiber-firebaseauth"
	"google.golang.org/api/option"
	"log"
	"os"
	"time"
)

func setupFirebaseApp(ctx context.Context) (*firebase.App, error) {
	// Initialize Firebase App
	opt := option.WithCredentialsFile(os.Getenv("FIREBASE_CREDS_JSON"))
	firebaseApp, err := firebase.NewApp(ctx, nil, opt)
	if err != nil {
		return nil, err
	}

	return firebaseApp, nil
}

func main() {
	// load godotenv
	err := godotenv.Load()
	if err != nil {
		log.Println("Error loading .env file")
	}

	// Create a new Fiber instance
	app := fiber.New(
		fiber.Config{
			EnablePrintRoutes: true,
		},
	)

	// create context with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// Initialize Firebase App
	FirebaseApp, err := setupFirebaseApp(ctx)
	if err != nil {
		log.Println("Error initializing Firebase App:", err)
		return
	}

	// setup firebaseapp
	app.Use(gofiberfirebaseauth.New(gofiberfirebaseauth.Config{
		FirebaseApp: FirebaseApp,
		IgnoreUrls:  []string{"GET::/", "POST::/signup"},
	}))

	app.Get("/", func(c *fiber.Ctx) error {
		return c.SendString("Hello, World 👋!")
	})
	// Protected route
	app.Get("/secure", func(c *fiber.Ctx) error {
		currentUser, ok := c.Locals("user").(gofiberfirebaseauth.User)
		if !ok {
			return c.Status(fiber.StatusUnauthorized).SendString("Unauthorized")
		}
		log.Println("Current User ID:", currentUser)
		return c.SendString("Welcome " + currentUser.UserID)
	})

	// Start the server on port 3001
	fErr := app.Listen(":3001")
	if fErr != nil {
		log.Println("Error starting the server:", fErr)
		return
	}
}
