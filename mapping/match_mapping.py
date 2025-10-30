import argparse
import os
import numpy as np
import pandas as pd


def match_condition_mapping():
    source_codes = os.path.join("vocab", "mapping", "condition_map.tsv")
    hira_map = os.path.join("vocab", "mapping", "hira_condition_map.csv")

    source_df = pd.read_csv(source_codes, delimiter="\t")
    map_df = pd.read_csv(hira_map)

    print(source_df.shape[0], source_df.상병코드.nunique())
    print(map_df.shape[0], map_df.LOCAL_CD1.nunique())

    merge_df = pd.merge(
        source_df,
        map_df[["LOCAL_CD1", "SOURCE_CONCEPT_ID"]],
        how="left",
        left_on="상병코드",
        right_on="LOCAL_CD1",
    )

    print(source_df)
    print(map_df)
    print(merge_df)


def match_drug_mapping():
    source_codes = os.path.join("vocab", "mapping", "drug_map.tsv")
    hira_map = os.path.join("vocab", "mapping", "hira_drug_map.csv")

    source_df = pd.read_csv(source_codes, delimiter="\t")
    map_df = pd.read_csv(hira_map)

    map_df = map_df[map_df.INVALID_REASON.isna()]

    print(source_df.shape[0], source_df.청구코드.nunique())
    print(map_df.shape[0], map_df.LOCAL_CD1.nunique())

    merge_df = pd.merge(
        source_df,
        map_df[["LOCAL_CD1", "TARGET_CONCEPT_ID_1", "SOURCE_CONCEPT_ID"]],
        how="left",
        left_on="청구코드",
        right_on="LOCAL_CD1",
    )

    print(source_df)
    print(map_df)
    print(merge_df)

    merge_df.TARGET_CONCEPT_ID_1.fillna(0, inplace=True)
    merge_df.SOURCE_CONCEPT_ID.fillna(0, inplace=True)

    merge_df.TARGET_CONCEPT_ID_1 = merge_df.TARGET_CONCEPT_ID_1.astype(
        np.int32, errors="ignore"
    )
    merge_df.SOURCE_CONCEPT_ID = merge_df.SOURCE_CONCEPT_ID.astype(
        np.int32, errors="ignore"
    )

    merge_df.TARGET_CONCEPT_ID_1 = merge_df.TARGET_CONCEPT_ID_1.astype(
        str, errors="ignore"
    )
    merge_df.SOURCE_CONCEPT_ID = merge_df.SOURCE_CONCEPT_ID.astype(str, errors="ignore")

    merge_df.loc[merge_df.TARGET_CONCEPT_ID_1 == "0", "TARGET_CONCEPT_ID_1"] = None
    merge_df.loc[merge_df.SOURCE_CONCEPT_ID == "0", "SOURCE_CONCEPT_ID"] = None

    print(merge_df)
    merge_df.to_csv(
        os.path.join("vocab", "mapping", "drug_merged_map.csv"), index=False
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("domain", type=str)

    args = parser.parse_args()

    if args.domain == "condition":
        match_condition_mapping()
    elif args.domain == "drug":
        match_drug_mapping()
