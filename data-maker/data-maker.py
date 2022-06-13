from faker import Faker
import random
import csv

num_records = 1_000_000
columns = ['id', 'name', 'job', 'company']

fake = Faker()

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

with open('data_complete.csv', 'w', newline='') as file:
    writer = csv.DictWriter(file, columns, delimiter=',')
    writer.writeheader()
    writer.writerows(data)
