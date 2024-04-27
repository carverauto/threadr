# ThreadR API

## New Users

```mermaid
flowchart TD
    A[User Signs Up] --> B{Firebase Auth}
    B --> C[User Added to Firebase under no tenant]
    C --> D[User logs into Dashboard]
    D --> E{User Belongs to a Tenant?}
    E -->|No| F[User can create or wait for an invitation to join a Tenant]
    E -->|Yes| G[Access Tenant-Specific Features]
    F --> H[User Creates a Tenant]
    F --> I[User Receives an Invitation]
    H --> J[User Joins Own Tenant]
    I --> J
    J --> G


### Explanation of Each Step:
- **A (User Signs Up)**: The user initiates the process by signing up through the app's registration interface.
- **B (Firebase Auth)**: The user's information is processed through Firebase Authentication.
- **C (User Added to Firebase under no tenant)**: Once authenticated, the user is added to Firebase with no specific tenant associated.
- **D (User logs into Dashboard)**: Post-registration, the user logs in and accesses the main dashboard.
- **E (User Belongs to a Tenant?)**: Check if the user is associated with any tenant.
  - **F (User can create or wait for an invitation to join a Tenant)**: If not part of a tenant, the user has the option to create a new tenant or wait to be invited to one.
  - **G (Access Tenant-Specific Features)**: If part of a tenant, the user can access features specific to that tenant.
- **H (User Creates a Tenant)**: The user decides to create a new tenant.
- **I (User Receives an Invitation)**: Alternatively, the user may receive an invitation to join an existing tenant.
- **J (User Joins Own Tenant or the Invited Tenant)**: The user joins either the tenant they created or the one they were invited to.

This flowchart helps in visualizing the step-by-step process of user onboarding and tenant association in your application, making it clear how new users are handled from signup to accessing tenant-specific functionalities.
