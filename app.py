from flask import Flask
app = Flask(__name__)


@app.route("/")
def home():
    return "Hello, Flask!"

# to run in terminal:
# export FLASK_APP=hello
# python -m flask run --host=0.0.0.0 --port=80
