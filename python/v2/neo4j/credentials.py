from modules.environment.environment_utilities import (
    load_environment_variables,
    verify_environment_variables,
)

# Load environment variables using the utility
env_vars = load_environment_variables()

# Verify the environment variables
if not verify_environment_variables(env_vars):
    raise ValueError("Some environment variables are missing!")

neo4j_credentials = {
    "url": env_vars["NEO4J_URI"],
    "username": env_vars["NEO4J_USERNAME"],
    "password": env_vars["NEO4J_PASSWORD"],
    "openai_api_secret_key": env_vars["OPEN_AI_SECRET_KEY"],
}
