# ------------------------------------------------------------------------------
# TANNIRS 
# Boscalia Technologies
# Noemi Álvarez Fernández and Manuel de Luque Ripoll
# 2023
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Libraries

library(tidyverse)
library(caret)
library(pROC)

# ------------------------------------------------------------------------------
# Data

nir  <- read.csv("../data/Espectros-NIR.csv",       sep = ";")
ftir <- read.csv("../data/Picos-FTIR-ATR.csv",      sep = ";")
gcms <- read.csv("../data/Cromatogramas-GC-MS.csv", sep = ";", check.names = FALSE)

# ------------------------------------------------------------------------------
# NIR models data set

nir_t <- t(nir[, -1])
colnames(nir_t) <- nir$WN

nir_m <- nir_t %>% 
  as_tibble() %>% 
  mutate(etiqueta = names(nir)[-1], 
         sp = as.factor(sub("^([[:alpha:]]*).*", "\\1", etiqueta)),
         .before = 1) %>%
  dplyr::filter(sp != "Blanco") %>%
  droplevels()

# Avespec (165 - 1100)
nir_avespec <- nir_m[, c(1, 2, which(names(nir_m) %in% 165:1100))]

# NirNano (1101 - 1700)
nir_nirnano <- nir_m[, c(1, 2, which(names(nir_m) %in% 1101:1700))]

# Avespec (165 - 1100) + NirNano (1101 - 1700) sin Nirone
nir_avespec_nirnano <- nir_m[, c(1, 2, which(names(nir_m) %in% 165:1700))]

# Espectros promedio
nir_m <- nir_m %>% 
  mutate(muestra = gsub("\\..*", "", etiqueta), .after = etiqueta)

nir_promedio <- aggregate(.~ muestra, data = nir_m[, -c(1, 3)], FUN = mean)
nir_promedio <- nir_promedio %>% mutate(sp = as.factor(sub("^([[:alpha:]]*).*", "\\1", nir_promedio$muestra)), .after = muestra)

# ------------------------------------------------------------------------------
# FTIR-ATR models data set

fitr_t <- t(ftir[, -1])
colnames(fitr_t) <- ftir$WN

fitr_m <- fitr_t %>% 
  as_tibble() %>% 
  mutate(etiqueta = names(ftir)[-1], 
         muestra = gsub("\\..*","", etiqueta),
         sp = as.factor(sub("^([[:alpha:]]*).*", "\\1", etiqueta)),
         .before = 1) %>%
  droplevels()

# ------------------------------------------------------------------------------
# GC-MS models data set

gcms_m <- gcms %>% 
  mutate(etiqueta = gsub(" ", "", etiqueta)) %>%
  mutate(muestra = gsub('-', '', etiqueta), .after = etiqueta,
         Compuestos_interes = as.factor(Compuestos_interes)) %>%
  select(muestra, Compuestos_interes, Area, `Area_%`, `Area_Sum_%`, concentracion_ppm)

# Total
nir_gcms <- merge(gcms_m, nir_promedio, by = "muestra", all.x = F, all.y = T)
nir_gcms <- nir_gcms %>% na.omit() %>% droplevels()

# Avespec (165 - 1100)
avespec_gcms <- nir_gcms[, c(1:7, which(names(nir_gcms) %in% 165:1100))]

# NirNano (1101 - 1700)
nirnano_gcms <- nir_gcms[, c(1:7, which(names(nir_gcms) %in% 1101:1700))]

# Avespec (165 - 1100) + NirNano (1101 - 1700) sin Nirone
avespec_nirnano_gcms <- nir_gcms[, c(1:7, which(names(nir_gcms) %in% 165:1700))]

# NIR + FTIR-ATR
nir_ftir_gcms <- merge(nir_gcms, fitr_m, by = "muestra", all.x = F, all.y = T) 
nir_ftir_gcms <- nir_ftir_gcms %>% na.omit() %>% droplevels() %>% select(-etiqueta)

# FTIR-ATR
ftir_gcms <- merge(gcms_m, fitr_m, by = "muestra", all.x = F, all.y = T) 
ftir_gcms <- ftir_gcms %>% na.omit() %>% droplevels() %>% select(-etiqueta)

# ------------------------------------------------------------------------------
# Models

data <- ftir_gcms # "set data: nir_gcms, nirnano_gcms, avespec_nirnano_cgms, nir_ftir_gcms, ftir_gcms"

set.seed(123)

pre_process <- c("center", "scale")

i <- createDataPartition(data$Compuestos_interes, p = .75, list = FALSE)

training_set <- data[i, ]
test_set <- data[-i, ]

tr_control <- trainControl(method = "repeatedcv", number = 10, repeats = 10)

set.seed(456)

m_fit <- train(Compuestos_interes ~ .,
               data = training_set[, -1], # -c(1, 3:5)
               method = "rf", # svmLinear
               metric = "Accuracy",
               preProcess = pre_process,
               trControl = tr_control)

pred <- predict(m_fit, test_set[, -1], probability=TRUE)
confusionMatrix(pred, test_set$Compuestos_interes)
multiclass.roc(test_set$Compuestos_interes, factor(pred, ordered = TRUE))
