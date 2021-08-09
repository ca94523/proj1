#in shell: export FLASK_APP=flaskpart1.py
#in shell: flask run

from flask import Flask
from flask import render_template


app = Flask(__name__)


@app.route('/')
@app.route('/index')
def index():
#    return "Hello, World!"

    user = {'username': 'Miguel'}
    return render_template('index.html', title='Home', user=user)
