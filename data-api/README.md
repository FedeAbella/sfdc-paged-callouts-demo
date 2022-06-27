# data-api: The Heroku api

This directory contains all the files needed to expose a Heroku app that returns the set of fake data created by [`data-maker`](https://github.com/FedeAbella/salesforce-paged-callouts-demo/tree/master/data-maker). These are:
- `Procfile` tells Heroku to expose a web worker using `gunicorn`
- `requirements.txt` and `runtime.txt` to tell Heroku which version and libraries of Python are needed for this to work as intended.
- `data-api.py` contains the main Flask app
- `dataset.py` pre-loads the entire csv dataset into a `pandas` DataFrame, and is imported as a module into `data-api.py` so gunicorn can use pre-loading and save on some memory
- `data_complete.csv` is just... well, the complete dataset in csv form.

## The existing endpoints

One version of the api is currently hosted [here](https://salesforce-paged-callouts-demo.herokuapp.com/). It contains:

- An "empty" `/` path. Ok, it's got some text, just so you get something back, but that really serves no purpose other than as placeholder
- `/data` exposes the data contained in `data_complete.csv` in a non-paged manner. This is used for showing how the Batch Apex job fails when GETting a large amount of data from a non-paged endpoint. It optionally takes in a URL parameter `size` with possible values `small`, `medium`, `large`, or `complete` (defaults to `complete`). Using this will return 0.1%, 1%, 10% or the full set of data, respectively.
- `/paged` returns the data using paging, so it can be asked for it in convenient chunks. It also takes the `size` parameter, same as the `data` endpoint, and this sets the max amount of data that will return (the last page, so to speak). This endpoint takes two **non** optional parameters: `start` and `end` which do exactly what you think they do. Rows are 1-indexed, and setting `start` or `end` larger than the size of the dataset (as modified by `size`) will result in no rows returned, or less rows returned than asked for, respectively.
- `/faulty` works exactly the same as `paged`, but has a built-in ~33% probability of just returning a 500: Internal Server Error code. Hey, it's faulty, it's right there in the name. Can't say I didn't warn you. This one is used for showing how the proposed solution in Apex handles re-trying failed callouts.

I'll try and keep the existing endpoint alive so long as it's not an inconvenience, and Heroku keeps it for free. So if it's still there, feel free to play around and get a feel as to what the data looks like and how each endpoint works. 
