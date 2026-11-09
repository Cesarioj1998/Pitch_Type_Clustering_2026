# ---- Pitch Type Clustering ----
# Can kmeans sort pitches into the right pitch types using only their measurements?
# hide the labels, cluster, then score

# Load packages
library(duckdb)
library(DBI)
library(dplyr)
library(cluster)
library(ggplot2)

# Connect to the existing Statcast database (built in Pitcher Analysis.R)
con <- dbConnect(duckdb(), dbdir = "statcast.duckdb")

# Read the SQL file and pull one row per pitcher per pitch type (50+ pitches)
pt_sql <- paste(readLines("Pitch_Type_Data.sql"), collapse = "\n")
pt <- dbGetQuery(con, pt_sql)

# Data check 1: total rows, plus how many rows fall under each label
# (the labels are only used for scoring, never in the clustering itself)
nrow(pt)
table(pt$family)
table(pt$pitch_label)

# ---- Step 2: test every predictor combination at k = 3 (Fastball, Offspeed, Breaking) ----

# Score a clustering:
# for each cluster, count the most common true label, add those counts up, divide by total rows
score_clusters <- function(clusters, labels) {
  tab <- table(clusters, labels)
  sum(apply(tab, 1, max)) / length(labels)
}

# The 4 measurements we can cluster on
predictors <- c("velo", "ivb", "hb", "spin")

# Standardize them so each one counts equally
pt_scaled <- scale(pt[, predictors])

# Build every possible combination of the 4 predictors (15 total: 4 singles, 6 pairs, 4 trios, all 4)
combo_list <- unlist(lapply(1:4, function(m) combn(predictors, m, simplify = FALSE)),
                     recursive = FALSE)

# Run kmeans with k = 3 on each combination and score it against the true family
results_k3 <- data.frame(predictors = character(), accuracy = numeric())
for (combo in combo_list) {
  set.seed(6501)
  km  <- kmeans(pt_scaled[, combo, drop = FALSE], centers = 3, nstart = 25)
  acc <- score_clusters(km$cluster, pt$family)
  results_k3 <- rbind(results_k3,
                      data.frame(predictors = paste(combo, collapse = " + "),
                                 accuracy   = round(acc * 100, 1)))
}

# Results table, best to worst
# (remember: 49.1% is the floor, since that's the share of fastballs)
results_k3 %>% arrange(desc(accuracy))

# ---- Step 2b: where does the best k = 3 model go wrong? ----

# Refit the best combination (all 4 predictors) so we can look at its clusters
set.seed(6501)
km3_best <- kmeans(pt_scaled[, predictors], centers = 3, nstart = 25)

# Which family each cluster mostly matched (the majority family in each cluster)
table(cluster = km3_best$cluster, family = pt$family)

# Same clusters, broken out by specific pitch type
# This shows exactly which pitch types are landing in the "wrong" family's cluster
table(cluster = km3_best$cluster, pitch = pt$pitch_label)

# ---- Step 3: suggest a value of k (elbow method plus silhouette) ----

# Try k = 2 through 10 using all 4 predictors, and record two measures for each:
# within_ss = how tight the clusters are (lower is tighter; look for the bend in the elbow)
# avg_silhouette = how well separated the clusters are (higher is better)
k_check <- data.frame(k = 2:10, within_ss = NA, avg_silhouette = NA)
pt_dist <- dist(pt_scaled[, predictors])

for (i in seq_along(k_check$k)) {
  set.seed(6501)
  km <- kmeans(pt_scaled[, predictors], centers = k_check$k[i], nstart = 25)
  k_check$within_ss[i]      <- round(km$tot.withinss, 1)
  k_check$avg_silhouette[i] <- round(mean(silhouette(km$cluster, pt_dist)[, "sil_width"]), 3)
}

# How much within_ss dropped from the previous k (where this levels off is the elbow)
k_check$ss_drop <- c(NA, round(-diff(k_check$within_ss), 1))
print(k_check)

# Plot both side by side
par(mfrow = c(1, 2))
plot(k_check$k, k_check$within_ss, type = "b",
     xlab = "Number of clusters (k)", ylab = "Within cluster sum of squares",
     main = "Pitch types: elbow")
plot(k_check$k, k_check$avg_silhouette, type = "b",
     xlab = "Number of clusters (k)", ylab = "Average silhouette width",
     main = "Pitch types: silhouette")
par(mfrow = c(1, 1))

# ---- Step 4: can kmeans recover the specific pitch types? (k = 7 and k = 8) ----

# For k = 7, fold sweepers into sliders so the labels match Savant's slider group
pt$label7 <- ifelse(pt$pitch_label == "Sweeper", "Slider", pt$pitch_label)

# k = 7 using all 4 predictors, scored against the 7 pitch groups
# (floor is about 23%, the share of four seamers)
set.seed(6501)
km7 <- kmeans(pt_scaled[, predictors], centers = 7, nstart = 25)
round(score_clusters(km7$cluster, pt$label7) * 100, 1)

# Which pitch types landed in each of the 7 clusters
table(cluster = km7$cluster, pitch = pt$pitch_label)

# k = 8 using all 4 predictors, scored against the 8 pitch labels (sweeper separate)
set.seed(6501)
km8 <- kmeans(pt_scaled[, predictors], centers = 8, nstart = 25)
round(score_clusters(km8$cluster, pt$pitch_label) * 100, 1)

# Which pitch types landed in each of the 8 clusters
table(cluster = km8$cluster, pitch = pt$pitch_label)

# ---- Step 5: describe the k = 8 clusters in real units ----

# Attach each row's k = 8 cluster
pt$km8 <- km8$cluster

# For each cluster: size, most common pitch label (and its share), and average measurements
# This is what lets us put a name on each cluster
k8_profile <- pt %>%
  group_by(cluster = km8) %>%
  summarise(rows       = n(),
            top_label  = names(which.max(table(pitch_label))),
            top_share  = round(max(table(pitch_label)) / n() * 100, 1),
            velo       = round(mean(velo), 1),
            ivb        = round(mean(ivb), 1),
            hb         = round(mean(hb), 1),
            spin       = round(mean(spin), 0),
            .groups    = "drop") %>%
  as.data.frame()
print(k8_profile)

# ---- Step 6: movement plots (Statcast labels vs kmeans clusters) ----

# Names for the 8 clusters, based on the k = 8 profile
# (the cluster numbers stay the same every run, since the SQL sorts the rows
#  and set.seed fixes the random starting points)
k8_names <- c("1" = "Run heavy changeup",
              "2" = "Sinker",
              "3" = "Traditional slider",
              "4" = "Low spin changeup / splitter",
              "5" = "Sweeper",
              "6" = "Cutter / gyro slider",
              "7" = "Four seamer",
              "8" = "Curveball")
pt$k8_name <- k8_names[as.character(pt$km8)]

# Baseball Savant style colors for each Statcast label (also sets the legend order)
label_colors <- c("Four Seamer" = "#D22D49",
                  "Sinker"      = "#FE9D00",
                  "Cutter"      = "#933F2C",
                  "Slider"      = "#EEE716",
                  "Sweeper"     = "#DDB33A",
                  "Curveball"   = "#00D1ED",
                  "Changeup"    = "#1DBE3A",
                  "Splitter"    = "#3BACAC")

# Matching colors for each cluster, using the Savant color of its closest pitch type
cluster_colors <- c("Four seamer"                  = "#D22D49",
                    "Sinker"                       = "#FE9D00",
                    "Cutter / gyro slider"         = "#933F2C",
                    "Traditional slider"           = "#EEE716",
                    "Sweeper"                      = "#DDB33A",
                    "Curveball"                    = "#00D1ED",
                    "Run heavy changeup"           = "#1DBE3A",
                    "Low spin changeup / splitter" = "#3BACAC")

# Build a Savant style movement plot for any grouping (Statcast label or cluster)
# Small faded dots = each pitcher's pitch type; big outlined circles = the average of each group
movement_plot <- function(data, group_col, colors, plot_title) {
  
  # Average movement for each group, used for the big center circles
  centers <- data %>%
    group_by(group = .data[[group_col]]) %>%
    summarise(hb = mean(hb), ivb = mean(ivb), .groups = "drop")
  
  ggplot(data, aes(x = hb, y = ivb)) +
    geom_hline(yintercept = 0, color = "grey60") +
    geom_vline(xintercept = 0, color = "grey60") +
    geom_point(aes(color = .data[[group_col]]), alpha = 0.35, size = 1.2) +
    geom_point(data = centers, aes(x = hb, y = ivb, fill = group),
               shape = 21, color = "black", size = 5, stroke = 1.2) +
    scale_color_manual(values = colors, guide = "none") +
    scale_fill_manual(values = colors, breaks = names(colors), name = NULL) +
    guides(fill = guide_legend(nrow = 2, override.aes = list(size = 4))) +
    coord_equal(xlim = c(-25, 25), ylim = c(-25, 25)) +
    labs(title   = plot_title,
         x       = "Horizontal Break (in), arm side +",
         y       = "Induced Vertical Break (in)",
         caption = "Each dot is one pitcher's pitch type (50+ thrown), 2026. Lefties mirrored.") +
    theme_minimal() +
    theme(plot.title       = element_text(face = "bold", hjust = 0.5),
          legend.position  = "bottom",
          panel.grid.minor = element_blank(),
          plot.caption     = element_text(color = "grey40", size = 8))
}

# Plot 1: colored by what Statcast calls each pitch
p_labels <- movement_plot(pt, "pitch_label", label_colors,
                          "Pitch Movement by Statcast Label")
print(p_labels)

# Plot 2: colored by kmeans cluster (k = 8)
p_clusters <- movement_plot(pt, "k8_name", cluster_colors,
                            "Pitch Movement by kmeans Cluster (k = 8)")
print(p_clusters)

# Save both plots as image files in the project folder (for the GitHub README)
ggsave("Movement_by_Statcast_Label.png", p_labels,   width = 7, height = 7.5, dpi = 300, bg = "white")
ggsave("Movement_by_Cluster.png",        p_clusters, width = 7, height = 7.5, dpi = 300, bg = "white")

# ---- Step 7: velo vs spin plot (shows why pitches that move alike got separated) ----

# Same Savant style as the movement plots, but with velo on the x axis and spin on the y axis
# Pitches that overlap on the movement chart (sinkers, changeups, splitters) should separate here
velo_spin_plot <- function(data, group_col, colors, plot_title) {
  
  # Average velo and spin for each group, used for the big center circles
  centers <- data %>%
    group_by(group = .data[[group_col]]) %>%
    summarise(velo = mean(velo), spin = mean(spin), .groups = "drop")
  
  ggplot(data, aes(x = velo, y = spin)) +
    geom_point(aes(color = .data[[group_col]]), alpha = 0.35, size = 1.2) +
    geom_point(data = centers, aes(x = velo, y = spin, fill = group),
               shape = 21, color = "black", size = 5, stroke = 1.2) +
    scale_color_manual(values = colors, guide = "none") +
    scale_fill_manual(values = colors, breaks = names(colors), name = NULL) +
    guides(fill = guide_legend(nrow = 2, override.aes = list(size = 4))) +
    labs(title   = plot_title,
         x       = "Velocity (mph)",
         y       = "Spin Rate (rpm)",
         caption = "Each dot is one pitcher's pitch type (50+ thrown), 2026.") +
    theme_minimal() +
    theme(plot.title       = element_text(face = "bold", hjust = 0.5),
          legend.position  = "bottom",
          panel.grid.minor = element_blank(),
          plot.caption     = element_text(color = "grey40", size = 8))
}

# Velo vs spin, colored by kmeans cluster
p_velo_spin <- velo_spin_plot(pt, "k8_name", cluster_colors,
                              "Velocity vs Spin by kmeans Cluster (k = 8)")
print(p_velo_spin)

# Save it for the README
ggsave("Velo_Spin_by_Cluster.png", p_velo_spin, width = 7, height = 6.5, dpi = 300, bg = "white")
