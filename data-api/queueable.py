from flask import Flask
from flask_restful import Resource, Api, reqparse
import pandas as pd

app = Flask(__name__)
api = Api(app)

df = pd.read_csv('data_complete.csv')
full_data = df.to_dict('records')
full_response= {
    'data':full_data
}

class Data(Resource):
    def get(self):
        return full_response, 200

api.add_resource(Data, '/data')

if __name__ == '__main__':
    app.run()