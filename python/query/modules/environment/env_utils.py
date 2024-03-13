# Create a utility module for environment variable handling

# Define a dictionary of expected environment variables
env_vars = {
    "OPEN_AI_SECRET_KEY": None,
    "NEO4J_URI": None,
    "NEO4J_USERNAME": None,
    "NEO4J_PASSWORD": None,
}


def load_environment_variables():
    """
    Loads and returns the required environment variables.
    """
    import os
    from environs import Env

    env = Env()
    env.read_env()  # reads .env file

    # Load environment variables from .env into the dictionary
    for key in env_vars:
        env_vars[key] = os.environ.get(key)

    return env_vars


def verify_environment_variables(env_vars):
    """
    Verifies that all required environment variables are set.
    Returns True if all are set, False otherwise.
    """
    all_env_vars_set = True

    for key, value in env_vars.items():
        if not value:
            print(f"{key} is not set!")
            all_env_vars_set = False

    return all_env_vars_set
