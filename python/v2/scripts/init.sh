# Remove preexisting virtual environment if it exists
rm -rf .venv

# Create a new virtual environment for the project
python3 -m venv .venv

# Activate your virtual environment
source .venv/bin/activate

# Install the packages from requirements.txt
pip install -r requirements.txt

# Load your environment variables (defined in ".env")
source .env
