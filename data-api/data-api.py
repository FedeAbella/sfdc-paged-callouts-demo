from crypt import methods
from flask import Flask
from flask_restful import Resource, Api, reqparse
import pandas as pd

app = Flask(__name__)
api = Api(app)

df = pd.read_csv('data_complete.csv')
<<<<<<< HEAD
full_data = df.to_dict('records')
full_response= {
    'data':full_data
=======
complete_data = df.to_dict('records')
complete_response = {
    'data':complete_data
>>>>>>> data-api
}

@app.route('/complete', methods=['GET'])
def get_complete_data():
    return complete_response, 200

@app.route('/partial', method=['GET'])
def get_partial_data():
    partial_data = df[:1000].to_dict('records')
    return {
        'data':partial_data
    }, 200

@app.route('/paged', methods=['GET'])
def get_paged_data():
    pass

if __name__ == '__main__':
    app.run()