# dataset.py
"""
Module for parsing the 'data_complete' csv file into a pandas dataframe
for preloading by gunicorn and avoiding repeated use of memory among different
workers
"""
from pandas import read_csv
DATASET = read_csv('data_complete.csv') # read the csv data into dataframe
