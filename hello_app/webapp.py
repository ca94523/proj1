# Entry point for the application.
from . import app    # For application discovery by the 'flask' command.
from . import views  # For import side-effects of setting up routes.

# to run in terminal:
# export FLASK_APP=webapp
# python -m flask run --host=0.0.0.0
# or
# flask run --host=0.0.0.0
