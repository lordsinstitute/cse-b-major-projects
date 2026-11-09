import pandas as pd

df = pd.read_csv("ml/data/cicids2017/MachineLearningCVE/Monday-WorkingHours.pcap_ISCX.csv")
df.columns = df.columns.str.strip()  # removes leading/trailing spaces from column names

print(df.shape)
print(df.columns.tolist())
print(df['Label'].value_counts())