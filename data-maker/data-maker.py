from faker import Faker
import random
import pandas as pd

num_records = 100_000

fake = Faker()
data = (
    {
        'name':fake.name(), 
        'id':str(random.randint(0,1_000_000_000)).zfill(10),
        'description':fake.text()
    } 
    for _ in range(num_records)
)

df = pd.DataFrame(data=data)
df.to_csv('data_complete.csv', index=False)
