# Clustering Pitch Types with kmeans: 2026 Pitches

## Goal

The goal of this project was to see whether a model could sort pitches into the right pitch types using only their measurements. If a model only knew a pitch's velocity, movement, and spin, and was never told what anyone called the pitch, could it group pitches the same way Statcast labels them?

I used kmeans clustering in R, a method that sorts data points into a chosen number of groups (called k) based on how similar their measurements are, and tested which combination of measurements did the best job. The four predictors were **velocity, induced vertical break, horizontal break, and spin rate**. The pitch type labels were hidden from the model and only used afterward to score how well it did.

**Full writeup:** [Clustering_Pitch_Types_kmeans_2026.docx](Clustering_Pitch_Types_kmeans_2026.docx)

## Key Results

| k | Scored against | Accuracy | Floor |
|---|---|---|---|
| 3 | Pitch family (Fastball, Breaking, Offspeed) | **93.6%** | 49.1% |
| 7 | 7 pitch groups (sweeper in slider) | **80.6%** | 23.2% |
| 8 | 8 pitch labels | **82.8%** | 23.2% |

* **Best combination of predictors:** all four together (93.6%). Spin rate was part of every one of the top five combinations, and velocity plus spin rate alone reached 91.3% with just two predictors.
* **Suggested k:** 3. The elbow plot bends most sharply at k = 3, and the silhouette width also peaked at k = 3 at 0.449.
* **Most of the misses came from cutters.** 100 of the 242 cutters (41%) landed outside the fastball cluster, which accounts for about 61% of all the misses. Without cutters, the model would have been right about 97.2% of the time.
* **kmeans found eight groups, but not Baseball Savant's eight.** It supported treating the sweeper as its own pitch, split changeups into two styles separated mainly by about 560 rpm of spin, and put most splitters inside the low spin changeup group.

## Charts

The two movement charts show the same pitches, first colored by what Statcast calls them and then colored by kmeans cluster. Each small dot is one pitcher's pitch type and each large outlined circle is the average of its group.

![Pitch movement by Statcast label](Pitch%20Clustering%20Plots/Pitch%20Movement%20by%20Statcast%20Label.png)

![Pitch movement by kmeans cluster](Pitch%20Clustering%20Plots/Pitch%20Movement%20by%20kmeans%20Cluster%20%28k%3D8%29.png)

On the velocity vs spin chart, the groups that overlapped in movement separate. Sinkers sit out around 94 mph, the run heavy changeup sits around 87 mph and 2,000 rpm, and the low spin changeup and splitter group drops to around 1,400 rpm. The reverse is also true. Four seamers and sinkers overlap here but were clearly apart on the movement chart, and curveballs and sweepers overlap here but sit in different spots on the movement chart.

![Velocity vs spin by kmeans cluster](Pitch%20Clustering%20Plots/Velocity%20vs%20Spin%20by%20kmeans%20Cluster%20%28k%3D8%29.png)

![Elbow and silhouette plots](Pitch%20Clustering%20Plots/Pitch%20Type%20Elbow%20Plot.png)

## Methodology

1. Every pitch from the 2026 regular season was pulled from Baseball Savant using the statcast_search function from the baseballr package and loaded into a DuckDB database, so the cleaning and summarizing could be done in SQL.
2. The pitches were cleaned in SQL. Pitch types that aren't normal pitches or are too rare to use were removed, break was converted from feet to inches, and horizontal break was mirrored for left handed pitchers so arm side movement is positive for everyone.
3. The pitches were grouped into one row per pitcher per pitch type, and only rows with at least 50 pitches thrown were kept. This left 2,574 rows.
4. CASE statements created two labels for each row: the pitch family and a pitch label with eight groups. Rare pitch types were folded into the closest group the same way Baseball Savant groups them.
5. The four predictors were standardized with scale(). They are on very different scales (spin rate is in the thousands while break is in inches), so without scaling, spin rate would have dominated the distance calculations.
6. Every possible combination of the four predictors (15 total) was tested with k = 3 (three groups, to match the three pitch families) and scored by counting the most common label in each cluster, adding those counts up, and dividing by the total number of rows (sometimes called cluster purity).
7. kmeans was run for every k from 2 to 10 to suggest a value of k, using the elbow method and the average silhouette width.
8. kmeans was run again with k = 7 and k = 8 to see if it could recover the specific pitch types, and each k = 8 cluster was named based on its averages.
9. Three charts were made with ggplot2 using Baseball Savant's pitch colors.

## The Eight Clusters (k = 8)

Velocity is in mph, IVB (induced vertical break) and HB (horizontal break) are in inches with arm side positive, and spin is in rpm.

| Cluster | Name | Most common label | Velo | IVB | HB | Spin |
|---|---|---|---|---|---|---|
| 7 | Four seamer | Four Seamer (92.5%) | 94.8 | 15.7 | 7.6 | 2,316 |
| 2 | Sinker | Sinker (88.7%) | 94.4 | 8.2 | 15.1 | 2,217 |
| 6 | Cutter / gyro slider | Cutter (69.7%) | 89.6 | 7.4 | -2.1 | 2,369 |
| 1 | Run heavy changeup | Changeup (75.1%) | 87.2 | 5.0 | 15.2 | 1,973 |
| 3 | Traditional slider | Slider (77.2%) | 86.0 | 0.2 | -4.2 | 2,432 |
| 4 | Low spin changeup / splitter | Changeup (69.6%) | 85.9 | 3.0 | 11.8 | 1,410 |
| 5 | Sweeper | Sweeper (83.7%) | 82.0 | 1.3 | -13.7 | 2,598 |
| 8 | Curveball | Curveball (92.9%) | 80.1 | -10.9 | -9.0 | 2,586 |

## Discussion

The biggest takeaway is that four simple measurements were enough for kmeans to put 93.6% of pitches into the right family without ever seeing a label. The key ingredient turned out to be spin rate paired with velocity. Fastballs are the hardest pitches with medium spin, breaking balls are slower with the most spin, and offspeed pitches are slower with the least spin, since killing spin is the whole idea behind a changeup or splitter.

Another takeaway is that the right combination of predictors mattered more than the number of them. All four together scored best, but velocity plus horizontal break scored 89.5%, adding vertical break dropped it to 80.0%, and only adding spin rate on top brought it back up.

Statcast files every cutter under fastballs, but about 41% of them looked more like breaking balls to the model. Some pitchers throw a firm cutter that plays like a fastball with a little cut, while others throw something closer to a hard, short slider. So the cutter isn't really one pitch, it's a range that sits between the fastball and the slider.

I think the k = 8 results come down to the difference between grip and shape. Some pitch labels describe how a pitch moves, while others describe how it's held. A splitter is a different grip than a changeup, and a knuckle curve is a different grip than a curveball, but they can produce the same shape. The model can only see the shape, so labels that are really about grip can't be recovered this way.

**Limitations:** each row is a pitcher's average for a pitch type, not individual pitches, and every row counts the same no matter how many pitches it's based on. The accuracy is measured against Statcast's labels, which aren't perfect themselves. At k = 7 and k = 8, two clusters can both count as changeups while splitters never count as correct, so the accuracy shows how pure the clusters are, not whether every pitch type got a group of its own. Splitters were also a small group at only 82 rows, and kmeans tends to look for round groups of similar size, which isn't a great fit for something like the cutter.

**Next steps:** cluster individual pitches for a single pitcher, add arm angle and release point, and try a clustering method that doesn't assume round groups, like a Gaussian mixture model.

## Files

| File | What it does |
|---|---|
| `Pitch Type Clustering.R` | Main script: pulls the clustering data from the database, runs every kmeans model, scores the results, and makes the charts |
| `Pitches_Clean.sql` | Run when building the database: cleans the raw pitch data (removes junk pitch types, converts break to inches, mirrors lefties) |
| `Pitch_Summary.sql` | Run when building the database: groups pitches into one row per pitcher per pitch type |
| `Pitch_Type_Data.sql` | Read by the main script: keeps rows with 50+ pitches and creates the family and pitch labels used for scoring |

The main script connects to a DuckDB database (`statcast.duckdb`) that was built beforehand. To build it, every 2026 regular season pitch was pulled from Baseball Savant with the statcast_search function in the baseballr package, loaded into DuckDB as a table called `pitches`, and then `Pitches_Clean.sql` and `Pitch_Summary.sql` were run. The raw data and the database aren't included in this repo because of their size.

The movement and velocity vs spin charts were saved with ggsave and renamed for this repo. The elbow plot was exported from RStudio's Plots window.

**Tools:** R (duckdb, DBI, dplyr, cluster, ggplot2), SQL (DuckDB), baseballr for the original data pull
