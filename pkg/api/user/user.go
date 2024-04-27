package user

import (
	firebase "firebase.google.com/go"
	"firebase.google.com/go/auth"
	"github.com/gofiber/fiber/v2"
	"time"
)

// CreateNewUser creates a new user account. The user's data is stored in
// Firestore. The Firestore structure is as follows:
// /users/{userId}
func CreateNewUser(app *firebase.App) fiber.Handler {
	return func(c *fiber.Ctx) error {
		// Parse the request body
		var body struct {
			Email    string `json:"email"`
			Password string `json:"password"`
			Phone    string `json:"phone"`
			Name     string `json:"name"`
			PhotoURL string `json:"photoURL"`
		}
		if err := c.BodyParser(&body); err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": "Cannot parse JSON",
			})
		}

		// Get context from fiber.Ctx
		ctx := c.Context()

		// Get the Firebase Auth client
		authClient, err := app.Auth(ctx)
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Failed to initialize Firebase Auth client",
			})
		}

		// Create a new user
		params := (&auth.UserToCreate{}).
			Email(body.Email).
			Password(body.Password).
			PhoneNumber(body.Phone).
			DisplayName(body.Name).
			PhotoURL(body.PhotoURL).
			Disabled(false)

		u, err := authClient.CreateUser(ctx, params)
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Failed to create user",
			})
		}

		// Return success message
		return c.Status(fiber.StatusCreated).JSON(fiber.Map{
			"message": "User created successfully",
			"user":    u.UID,
		})
	}
}

// CreateNewTenant creates a new tenant, which is a group of users
// with a shared set of permissions and resources. The user who creates
// the tenant is automatically assigned the role of tenant admin. Tenant
// admins can add and remove members, assign roles, and perform other
// administrative tasks. The data is stored in Firestore.
// The FireStore structure is as follows:
// /tenants/{tenantId}
//
//	/metadata { name, createdBy, ...}
//	/members/{userId} { role, joinedDate, ...}
func CreateNewTenant(app *firebase.App) fiber.Handler {
	return func(c *fiber.Ctx) error {
		// Parse the request body
		var body struct {
			Name string `json:"name"`
		}
		if err := c.BodyParser(&body); err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": "Cannot parse JSON",
			})
		}

		// Get Firestore client
		ctx := c.Context()
		client, err := app.Firestore(ctx)
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Failed to initialize Firestore client",
			})
		}
		defer client.Close()

		// Check if tenant already exists
		tenants := client.Collection("tenants")
		dsnap, err := tenants.Doc(body.Name).Get(ctx)
		if err == nil && dsnap.Exists() {
			return c.Status(fiber.StatusConflict).JSON(fiber.Map{
				"error": "Tenant already exists",
			})
		}

		// Create new tenant
		_, err = tenants.Doc(body.Name).Set(ctx, map[string]interface{}{
			"metadata": map[string]interface{}{
				"name":      body.Name,
				"createdBy": getUserIdFromToken(c, app),
			},
			"members": map[string]interface{}{
				"user_id": map[string]interface{}{ // Replace with actual user ID
					"role":       "admin",
					"joinedDate": time.Now(),
				},
			},
		})
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Failed to create tenant",
			})
		}

		// Return success message
		return c.Status(fiber.StatusCreated).JSON(fiber.Map{
			"message": "Tenant created successfully",
			"tenant":  body.Name,
		})
	}
}

func getUserIdFromToken(c *fiber.Ctx, app *firebase.App) (string, error) {
	// Get the ID token from the Authorization header
	idToken := c.Get("Authorization")

	// Get context from fiber.Ctx
	ctx := c.Context()

	// Get the Firebase Auth client
	authClient, err := app.Auth(ctx)
	if err != nil {
		return "", err
	}

	// Verify the ID token
	token, err := authClient.VerifyIDToken(ctx, idToken)
	if err != nil {
		return "", err
	}

	// Extract the user ID from the token's claims
	userId := token.UID

	return userId, nil
}

func MigrateUserToTenant(app *firebase.App) fiber.Handler {
	return func(c *fiber.Ctx) error {
		return c.SendString("Migrate user to tenant")
	}
}

func SetMemberRole(app *firebase.App) fiber.Handler {
	return func(c *fiber.Ctx) error {
		// Requestor must be a tenant admin
		return c.SendString("Set member role")
	}
}

func RemoveMember(app *firebase.App) fiber.Handler {
	return func(c *fiber.Ctx) error {
		// Requestor must be a tenant admin
		return c.SendString("Remove member")
	}
}

func tenantNameExists(app *firebase.App) fiber.Handler {
	return func(c *fiber.Ctx) error {
		return c.SendString("Check if tenant name exists")
	}
}

// initialRoleAssignment assigns the initial role to a tenant admin
func initialRoleAssignment(app *firebase.App) fiber.Handler {
	return func(c *fiber.Ctx) error {
		return c.SendString("Assign initial role")
	}
}
