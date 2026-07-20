# Healthcare Admissions Analysis — SQL + Power BI

A data analytics and visualization project examining admissions, length of stay, and billing across eight medical conditions in a **synthetic** healthcare dataset of 55,500 admission records. SQL handles cleaning, transformation, and analysis; Power BI delivers the dashboard.

> Demonstration project built on a synthetic dataset. Figures describe patterns within the data and are not real-world clinical findings. Relationships shown are descriptive associations, not causal claims.

## Contents
- `healthcare_final_cleaning_and_analysis.sql` — cleaning, transformation, and analysis queries
- `healthcare_analysis_ready_revised.csv` — analysis-ready dataset (55,500 rows)
- `Healthcare_Admissions_Dashboard.pbix` — Power BI dashboard
- `Healthcare_Admissions_Final_Report.pdf` — summary, methodology, findings, and recommendations
- `Healthcare_PowerBI_Development_Report.pdf` — dashboard development notes
- `Admissions_Overview_Dashboard.png`, `Clinical_Financial_Analysis_Dashboard.png` — dashboard screenshots

## A few findings
- Length of stay was validated against the admission-to-discharge date calculation across all 55,500 rows, with zero mismatches.
- The highest-billing condition (Cancer, about $64.5K on average) is not the longest-staying one (Alzheimer's, about 54 days on average), so billing and length of stay rank conditions differently.
- Average billing rises with age band across the dataset.

## Tools
SQL (SQLite via DB Browser), Power BI.

## Author
Eric Benitez
