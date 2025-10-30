import os
import pandas as pd

total_map_file = os.path.join("vocab", "mapping", "hira_map.csv")

df = pd.read_csv(total_map_file)

for source_domain_id, group_df in df.groupby("SOURCE_DOMAIN_ID"):
    group_df.to_csv(
        os.path.join("vocab", "mapping", f"hira_{source_domain_id.lower()}_map.csv"),
        index=False,
    )
