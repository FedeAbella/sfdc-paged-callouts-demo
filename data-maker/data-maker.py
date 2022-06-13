# data-maker.py
"""
An extremely simple script that uses faker to create a large csv of 
seemingly real data.
"""
from faker import Faker
import random
import csv

num_records = 1_000_000 # number of records to create
columns = ['id', 'name', 'job', 'company'] # column names

fake = Faker() # instatiate Faker

# use faker to create the data
data = (
    {
        'id': chr(random.randint(65,90)) +
            chr(random.randint(65,90)) +
            chr(random.randint(65,90)) +
            str(random.randint(0,1_000_000_000)).zfill(10),
        'name': fake.name(), 
        'job': fake.job(),
        'company': fake.company()
    } 
    for _ in range(num_records)
)

# write the data to a csv
with open('data_complete.csv', 'w', newline='') as file:
    writer = csv.DictWriter(file, columns, delimiter=',')
    writer.writeheader()
    writer.writerows(data)
