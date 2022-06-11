from crypt import methods
from flask import Flask
from flask_restful import Resource, Api, reqparse
import pandas as pd

app = Flask(__name__)
api = Api(app)

df = pd.read_csv('data_complete.csv')
complete_data = df.to_dict('records')
complete_response = {
    'data':complete_data
}

@app.route('/complete', methods=['GET'])
def get_complete_data():
    return complete_response, 200

@app.route('/partial', methods=['GET'])
def get_partial_data():
    partial_data = df[:1000].to_dict('records')
    return {
        'data':partial_data
    }, 200

@app.route('/paged', methods=['GET'])
def get_paged_data():
    pass

@app.route('/')
def index():
    return '<h1>This is empty...</h1>\n<p>(...yeah, I know)</p>'

if __name__ == '__main__':
    app.run()