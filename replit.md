# Flask Hello App

## Overview
A Flask web application with Home, About, Contact pages and a simple API endpoint.

## Project Structure
```
hello_app/
  __init__.py    - Flask app initialization
  views.py       - Route definitions
  templates/     - HTML templates
  static/        - Static files (CSS, JSON data)
main.py          - Entry point for running the app
```

## Running the App
The app runs on port 5000. Use the workflow to start it:
```
python main.py
```

## Routes
- `/` - Home page
- `/about/` - About page
- `/contact/` - Contact page
- `/hello/` - Hello page (accepts optional name parameter)
- `/api/data` - Returns JSON data

## Deployment
Configured for autoscale deployment using gunicorn.
