#' ###
#' Simulating joint data to fit a joint model to.
#' Taking work started in Simulating_JM_Int_MoreCovariates.R
#' and adding random slope to model specifications.
#' Latent association therefore dependent on R.E: Intercept and Slope (gamma_1 and gamma_2)
#' in Henderson 2000.
#' ###

# Prerequisites ------------------------------------------------------------
dev.off()
rm(list = ls())
library(tidyverse)
theme_set(theme_light())
library(lme4)
library(survival)

# Setting-out the scenario ------------------------------------------------
# Some diabetes trial, higher value of outcome is worse.
# Binary covariate is receiving treatment (yes = good)
# Factor covariate is BMI category at baseline (fat = bad)
# Continuous covariate is age at baseline (older = bad)
# Six treatment times (t)

# Single run --------------------------------------------------------------
# (will functionise afterwards)

# 'Global' parameters //
n_i <- 6 
m <- 250
N <- n_i * m
rho <- 0.3
sigma.i <- 3   # Random intercept SD
sigma.s <- 2   # Random slope SD
sigma.e <- 1.5 # Epsilon SD

# Covariance matrix //
sigma <- matrix(
  c(sigma.i ^ 2, rho * sigma.i * sigma.s,
  rho * sigma.i * sigma.s, sigma.s^2), nrow = 2, byrow = T
)

# Generate Random effects //
RE <- MASS::mvrnorm(m, c(0,0), sigma)
Ui <- RE[, 1]; Us <- RE[, 2] # Intercept; Slope

# Covariates - baseline //
id <- 1:m
x1 <- rbinom(m, 1, 0.5) # Treatment received
x2 <- gl(3, 1, m) # Factor
x3 <- floor(rnorm(m, 65, 10)) # Age

# Longitudinal part //
# Coefficients
b0 <- 40; b1 <- -10; b22 <- 5; b23 <- 15; b3 <- 0.1
Bl <- matrix(c(b0, b1, b22, b23, b3), nrow = 1) # Cast to matrix
# Baseline covariates
x1_l <- rep(x1, each = n_i)
x2_l <- rep(x2, each = n_i)
x3_l <- rep(x3, each = n_i)
Xl <- model.matrix(~x1_l+x2_l+x3_l)
time <- rep(0:(n_i-1), m)
# REs
U1l <- rep(Ui, each = n_i)
U2l <- rep(Us, each = n_i)
epsilon <- rnorm(N, 0, sigma.e)
# Response
Y <- Xl %*% t(Bl) + U1l + U2l * time + epsilon
# Data and quick model
long_data <- data.frame(id = rep(id, each = n_i), x1_l, x2_l, x3_l, time, Y)
summary(lmer(Y ~ x1_l + x2_l + x3_l + time + (1+time|id), data = long_data)) # Cool!

# Survival part //
lambda <- 0.05
b1s <- -0.3 # log-odds associated with having treatment (30% HR reduction)
b3s <- 0.05 # log-odds associated with one unit increase age (5% HR increase)  
Bs <- matrix(c(b1s, b3s), nrow = 1)
Xs <- model.matrix(~ x1 + x3 - 1)
  
# Simulate survival times
uu <- runif(m)
tt <- -log(uu)/(lambda * exp(Xs %*% t(Bs) + Ui + Us))
# Censoring
censor <- rexp(m, 0.01)
survtime <- pmin(tt, censor, 5)
status <- ifelse(survtime == tt, 1, 0)

surv_data <- data.frame(id, x1, x3, survtime, status)

summary(coxph(Surv(survtime, status) ~ x1 + x3, data = surv_data)) # Way further off than just R.I!

# Cast to class "jointdata"

jd <- joineR::jointdata(
  longitudinal = long_data,
  survival = surv_data,
  time.col = "time",
  id.col = "id",
  baseline = surv_data[, c("id", "x1", "x3")]
)

summary(joineR::joint(
  data = jd,
  long.formula = Y ~ x1_l + x2_l + x3_l + time,
  surv.formula = Surv(survtime, status) ~ x1 + x3
)) # Cool cool!


# Functionise -------------------------------------------------------------
# Just random intercept again!

joint_sim <- function(m = 200, n_i = 6, 
                      Bl = c(40, -10, 5, 15, 0.1), # Longit: Intercept, binary, factor2-3, continuous
                      Bs = c(-0.3, 0.05), # Survival: log-odds binary and continuous,
                      sigma.i = 1.5, sigma.e = 2.5,
                      lambda = 0.005){
  # Set out variables
  N <-  m * n_i
  id <- 1:m
  time <- 0:(n_i-1)
  tau <- max(time) 
  U_int <- rnorm(m, 0, sigma.i) # Random effects
  epsilon <- rnorm(N, 0, sigma.e)
  # Baseline covariates
  x1 <- rbinom(m, 1, 0.5) # Treatment received
  x2 <- gl(3, 1, m) # Factor
  x3 <- floor(rnorm(m, 65, 7)) # Age
  id <- 1:m
  
  # Longitudinal part //
  Bl <- matrix(Bl, nrow = 1) # Coefficients
  x1l <- rep(x1, each = n_i)
  x2l <- rep(x2, each = n_i)
  x3l <- rep(x3, each = n_i)
  Xl <- model.matrix(~x1l+x2l+x3l)
  Ul <- rep(U_int, each = n_i)

  Y <- Xl %*% t(Bl) + Ul + epsilon
  
  long_dat <- data.frame(id = rep(id, each = n_i),
                         time = rep(time, m),
                         x1l, x2l, x3l, Y)
  
  # Survival part //
  Bs <- matrix(Bs, nrow = 1)
  Xs <- model.matrix(~x1+x3-1)
  # Survival times
  u <- runif(m)
  tt <- -log(u)/(lambda * exp(Xs %*% t(Bs) + U_int))
  
  # Censoring and truncation
  rateC <- 0.001
  censor <- rexp(m, rateC)
  survtime <- pmin(tt, censor, tau) # time to output
  status <- ifelse(survtime == tt, 1, 0)
  
  surv_dat <- data.frame(id, x1, x3, survtime, status)
  
  # Extra output - number of events
  pc_events <- length(which(survtime < tau))/m * 100
  
  return(list(long_dat, surv_dat, pc_events))
  
}

temp <- joint_sim()
summary(lmer(Y ~ x1l + x2l + x3l + time + (1|id), data = temp[[1]]))
summary(coxph(Surv(survtime, status) ~ x1 + x3, data = temp[[2]]))


# Separate investigation --------------------------------------------------
# Should illustrate need for JM
separate_fits <- function(df){
  lmm_fit <- lmer(Y ~ x1l + x2l + x3l + time + (1|id), data = df[[1]])
  surv_fit <- coxph(Surv(survtime, status) ~ x1 + x3, data = df[[2]])
  return(
    list(lmm_fit, surv_fit)
  )
}

pb <- progress::progress_bar$new(total = 1000)
longit_beta <- data.frame(beta0 = NA, beta1 = NA, beta22 = NA, beta23 = NA, beta3 = NA, sigma.e = NA, sigma.u = NA)
surv_beta <- data.frame(beta1s = NA, beta3s = NA)
pc_events <- c()

for(i in 1:1000){
  dat <- joint_sim()
  pc_events[i] <- dat[[3]]
  fits <- separate_fits(dat)
  long_coefs <- fits[[1]]@beta[1:5]
  long_sigma.e <- sigma(fits[[1]])
  long_sigma.u <- as.numeric(attr(VarCorr(fits[[1]])$id, "stddev"))
  longit_beta[i,] <- c(long_coefs, long_sigma.e, long_sigma.u)
  surv_beta[i, ] <- as.numeric(fits[[2]]$coefficients)
  pb$tick()
}


ex <- expression
to_plot <- cbind(longit_beta, surv_beta, pc_events) %>% tibble %>% 
  gather("parameter", "estimate") %>% 
  mutate(param = factor(parameter, levels = c("beta0", "beta1", "beta22", "beta23", "beta3", "sigma.e", "sigma.u",
                                              "beta1s", "beta3s", "pc_events"),
                        labels = c(ex(beta[0]), ex(beta[1]), ex(beta[22]), ex(beta[23]), ex(beta[3]),
                                   ex(sigma[e]), ex(sigma[u]), ex(beta[1*"S"]), ex(beta[3*"S"]), ex("Events")))
         )

plot_lines <- to_plot %>% distinct(param)
plot_lines$xint <- c(40, -10, 5, 15, 0.1, 2.5, 1.5, -0.3, 0.05, NA)

to_plot %>% 
  ggplot(aes(x = estimate)) + 
  geom_density(fill = "grey20", alpha = .2) + 
  geom_vline(data = plot_lines, aes(xintercept = xint), colour = "blue", alpha = .5, lty = 3) + 
  facet_wrap(~param, scales = "free", nrow = 5, ncol = 2, labeller = label_parsed) + 
  labs(title = "Separate investigation", x = "Estimate")
ggsave("./JM-sims-plots/Separate_Investigation.png")



# Joint investigation -----------------------------------------------------
library(joineR)

long_dat <- joint_sim()[[1]]
surv_dat <- joint_sim()[[2]]

# Single-run
temp <- left_join(long_dat, surv_dat, "id")

long_dat2 <- temp %>% 
  filter(time <= survtime) %>% 
  dplyr::select(names(long_dat))

jd <- jointdata(
  longitudinal = long_dat2,
  survival = surv_dat,
  id.col = "id",
  time.col = "time",
  baseline = surv_dat[,c("id", "x1", "x3")]
)

joint_fit <- joint(jd,
      long.formula = Y ~ x1l + x2l + x3l + time,
      surv.formula = Surv(survtime, status) ~ x1 + x3,
      model = "int") # Sepassoc doesn't matter as only one L.A.

summary(joint_fit)