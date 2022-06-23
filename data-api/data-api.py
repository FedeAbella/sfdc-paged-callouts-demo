# data-api.py
"""
This is a simple Flask api that returns some data saved into a
    'data_complete.csv' file in the root script directory.

Endpoints:
    /complete: Returns a 200 code, and a JSON with the key 'data' containing
        the full dataset
    /partial: Returns a 200 code, and a partial set of data, formatted as with
        /complete, and taken from the top. Takes the URL parameter 'size', with
        values 'small', 'medium', 'large' (default 'small'), and returns the 
        first 0.1%, 1%, or 10% records, rounded down. The 'data' key will be 
        empty if the parameter value is not enough to return at least 1 record.
    /random: Works as /partial, but the data is taken at random from the entire
        dataset. Rows are randomized as well.
    /paged: Takes in two URL parameters ('start' and 'end'), and returns the
        rows of data in between (first row is #1). If 'start' is larger than 
        the dataset size, the 'data' key in response is empty. If 'start' is
        within the dataset but 'end' is larger than the size, returns as much
        as it can.
    /: Just a simple html index page, to avoid 404.
"""
from flask import Flask, request, jsonify
from math import floor
from random import random, seed
from dataset import DATASET

app = Flask(__name__) # define the Flask app

TOTAL_ROWS = DATASET.shape[0]

# map the values of the size parameter to the percentage of rows returned
PARTIAL_SIZES = {
    'small': 0.001,
    'medium': 0.01,
    'large': 0.1
}

FAILURE_PROB = 0.5 # Probabiliy that a call to the 'faulty' endpoint fails
seed(a=None) # Initialize random to current time

@app.route('/complete', methods=['GET'])
def get_complete_data():
    """
    Returns the complete dataset as a JSON with the 'data' key containing it
    """
    return jsonify(
        {
            'success': True,
            'data': DATASET.to_dict('records')
        }
    ), 200

@app.route('/partial', methods=['GET'])
def get_partial_data():
    """
    Returns a partial set of data, taken from the top. Takes the URL parameter
    'size' with values 'small', 'medium', 'large' (default 'small') and returns
    the top 0.1%, 1% or 10% of data respectively. Returns 400 and error message
    if wrong parameter value is passed.
    """
    response = {}

    # check for the right parameter value, or none passed (default to small)
    size = request.args.get('size', 'small')
    if size not in PARTIAL_SIZES.keys():
        # if passed the wrong parameter, return 400 and error message
        response['success'] = False
        response['error'] = "'size' parameter takes only values 'small',"\
            " 'medium' or 'large'."
        return jsonify(response), 400

    # calculate number of rows to return, and default 'data' key to empty
    rows_to_return = floor( TOTAL_ROWS * PARTIAL_SIZES.get(size) )
    response['success'] = True
    response['data'] = []
    # if there's anything to return, overwrite the 'data' key with those rows
    if rows_to_return > 0:
        response['data'] = DATASET[:rows_to_return].to_dict('records')

    return jsonify(response), 200

@app.route('/random', methods=['GET'])
def get_random_data():
    """
    Returns a random subset of data. Works the same as /partial, but instead
    of taking the top portion of the data, it samples the appropriate amount of
    rows and shuffles them before returning.
    """
    response = {}

    # check for the right parameter value, or none passed (default to small)
    size = request.args.get('size', 'small')
    if size not in PARTIAL_SIZES.keys():
        # if passed the wrong parameter, return 400 and error message
        response['success'] = False
        response['error'] = "'size' parameter takes only values 'small',"\
            " 'medium' or 'large'."
        return jsonify(response), 400

    # calculate number of rows to return, and default 'data' key to empty
    rows_to_return = floor( TOTAL_ROWS * PARTIAL_SIZES.get(size) )
    response['success'] = True
    response['data'] = []
    # if there's anything to return, get a random sample of data and use that
    if rows_to_return > 0:
        response['data'] = DATASET.sample(rows_to_return).to_dict('records')

    return jsonify(response), 200


@app.route('/paged', methods=['GET'])
def get_paged_data():
    """
    Returns a paged portion of the data. Takes in two required, positive
    integer parameters: 'start' and 'end', with 'end' >= 'start'. Returns all
    rows between 'start' and 'end' (included) as a list in the 'data' key. 
    First row is numbered 1. If 'start' is larger than the dataset size, 
    returns an empty list in the key. If 'end' is larger than the dataset size,
    returns as much as possible. If any parameter is missing or not valid, 
    returns 400 and an error message.
    """

    # get the 'start' and 'end' parameters
    start = request.args.get('start', None)
    end = request.args.get('end', None)

    response = {}

    # check both parameters are present
    if not start or not end:
        response['success'] = False
        response['error'] = "Both a 'start' and 'end' parameters are required."
        return jsonify(response), 400

    # check both parameters are valid
    if not start.isdigit() or \
        not end.isdigit() or \
        int(start) == 0 or \
        int(end) == 0:
        response['success'] = False
        response['error'] = "'start' and 'end' parameters must be" \
            " positive integers."
        return jsonify(response), 400

    start, end = int(start), int(end)

    # check 'start' is not larger than 'end'
    if end < start:
        response['sucess'] = False
        response['error'] = "'start' cannot be larger than 'end'."
        return jsonify(response), 400
    
    response['success'] = True
    response['data'] = []

    # return an empty list if 'start' larger than dataset size
    if start > TOTAL_ROWS:
        return jsonify(response), 200
    # return the appropriate row if both 'start' and 'end' are the same
    if start == end:
        response['data'] = DATASET.iloc[[start-1]].to_dict('records')
        return jsonify(response), 200
    # return the remaining rows if 'end' is larger than dataset size
    if end > TOTAL_ROWS:
        response['data'] = DATASET[start-1:].to_dict('records')
        return jsonify(response), 200
    # return the dataframe splice between 'start' and 'end'
    response['data'] = DATASET[start-1:end].to_dict('records')
    return jsonify(response), 200

@app.route('/faulty', methods=['GET'])
def get_faulty_data():
    """
    Returns a paged portion of the data. Takes in two required, positive
    integer parameters: 'start' and 'end', with 'end' >= 'start'. Returns all
    rows between 'start' and 'end' (included) as a list in the 'data' key. 
    First row is numbered 1. If 'start' is larger than the dataset size, 
    returns an empty list in the key. If 'end' is larger than the dataset size,
    returns as much as possible. If any parameter is missing or not valid, 
    returns 400 and an error message.
    """

    # There's a probability that the endpoint simply returns a server error
    if (random() < FAILURE_PROB):
        return 500

    # get the 'start' and 'end' parameters
    start = request.args.get('start', None)
    end = request.args.get('end', None)

    response = {}

    # check both parameters are present
    if not start or not end:
        response['success'] = False
        response['error'] = "Both a 'start' and 'end' parameters are required."
        return jsonify(response), 400

    # check both parameters are valid
    if not start.isdigit() or \
        not end.isdigit() or \
        int(start) == 0 or \
        int(end) == 0:
        response['success'] = False
        response['error'] = "'start' and 'end' parameters must be" \
            " positive integers."
        return jsonify(response), 400

    start, end = int(start), int(end)

    # check 'start' is not larger than 'end'
    if end < start:
        response['sucess'] = False
        response['error'] = "'start' cannot be larger than 'end'."
        return jsonify(response), 400
    
    response['success'] = True
    response['data'] = []

    # return an empty list if 'start' larger than dataset size
    if start > TOTAL_ROWS:
        return jsonify(response), 200
    # return the appropriate row if both 'start' and 'end' are the same
    if start == end:
        response['data'] = DATASET.iloc[[start-1]].to_dict('records')
        return jsonify(response), 200
    # return the remaining rows if 'end' is larger than dataset size
    if end > TOTAL_ROWS:
        response['data'] = DATASET[start-1:].to_dict('records')
        return jsonify(response), 200
    # return the dataframe splice between 'start' and 'end'
    response['data'] = DATASET[start-1:end].to_dict('records')
    return jsonify(response), 200

@app.route('/')
def index():
    """
    Root url index page. Just some simple placeholder html.
    """
    return '<h1>This is empty...</h1>\n<p>(...yeah, I know)</p>'

if __name__ == '__main__':
    app.run() # run the app