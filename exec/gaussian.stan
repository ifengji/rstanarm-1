# GLM for a Gaussian outcome with Gaussian or t priors
functions {
  /** 
   * Apply inverse link function to linear predictor
   *
   * @param eta Linear predictor vector
   * @param link An integer indicating the link function
   * @return A vector, i.e. inverse-link(eta)
   */
  vector linkinv_gauss(vector eta, int link) {
    if (link < 1 || link > 3) reject("Invalid link");
    if (link == 1 || link == 2) # link = identity or log 
      return(eta); # return eta for log link too bc will use lognormal
    else {# link = inverse
      vector[rows(eta)] mu;
      for(n in 1:rows(eta)) mu[n] <- inv(eta[n]); 
      return mu;
    }
  }
  
  /** 
   * Pointwise (pw) log-likelihood vector
   *
   * @param y The integer array corresponding to the outcome variable.
   * @param link An integer indicating the link function
   * @return A vector
   */
  vector pw_gauss(vector y, vector eta, real sigma, int link) {
    vector[rows(eta)] ll;
    if (link < 1 || link > 3) reject("Invalid link");
    if (link == 2) # link = log
      for (n in 1:rows(eta)) ll[n] <- lognormal_log(y[n], eta[n], sigma);
    else { # link = idenity or inverse
      vector[rows(eta)] mu;
      mu <- linkinv_gauss(eta, link);
      for (n in 1:rows(eta)) ll[n] <- normal_log(y[n], mu[n], sigma);
    }
    return ll;
  }
}
data {
  # dimensions
  int<lower=1> N; # number of observations
  int<lower=1> K; # number of predictors
  
  # data
  vector[K] xbar;                # predictor means
  matrix[N,K]  X;                # centered predictor matrix
  vector[N]    y;                # continuous outcome
  int<lower=0,upper=1> prior_PD; # flag indicating whether to draw from the prior predictive
  
  # intercept
  int<lower=0,upper=1> has_intercept; # 1 = yes
  
  # link function from location to linear predictor
  int<lower=1,upper=3> link; # 1 = identity, 2 = log, 3 = inverse
  
  # weights
  int<lower=0,upper=1> has_weights; # 0 = No, 1 = Yes
  vector[N * has_weights] weights;
  
  # offset
  int<lower=0,upper=1> has_offset;  # 0 = No, 1 = Yes
  vector[N * has_offset] offset;
  
  # prior family (zero indicates no prior!!!)
  int<lower=0,upper=2> prior_dist;               # 1 = normal, 2 = student_t
  int<lower=0,upper=2> prior_dist_for_intercept; # 1 = normal, 2 = student_t
  
  # hyperparameter values are set to 0 if there is no prior
  vector<lower=0>[K] prior_scale;
  real<lower=0> prior_scale_for_intercept;
  vector[K] prior_mean;
  real prior_mean_for_intercept;
  vector<lower=0>[K] prior_df;
  real<lower=0> prior_df_for_intercept;
  real<lower=0> prior_scale_for_dispersion;
}
parameters {
  real gamma[has_intercept];
  vector[K] z_beta;
  real<lower=0> sigma_unscaled;
}
transformed parameters {
  vector[K] beta;
  real sigma;
  if (prior_dist > 0) beta <- prior_mean + prior_scale .* z_beta;
  else beta <- z_beta;
  if (prior_scale_for_dispersion > 0)
    sigma <-  prior_scale_for_dispersion * sigma_unscaled;
  else sigma <- sigma_unscaled;
}
model {
  vector[N] eta; # linear predictor
  eta <- X * beta;
  if (has_intercept == 1) eta <- eta + gamma[1];
  if (has_offset == 1)    eta <- eta + offset;
  
  // Log-likelihood 
  if (has_weights == 0 && prior_PD == 0) { # unweighted log-likelihoods
    vector[N] mu;
    mu <- linkinv_gauss(eta, link);
    if (link == 2)
      y ~ lognormal(mu, sigma);
    else 
      y ~ normal(mu, sigma);
  }
  else if (prior_PD == 0) { # weighted log-likelihoods
    vector[N] summands;
    summands <- pw_gauss(y, eta, sigma, link);
    increment_log_prob(dot_product(weights, summands));
  }
  
  // Log-prior for scale
  if (prior_scale_for_dispersion > 0) sigma_unscaled ~ cauchy(0, 1);
  
  // Log-priors for coefficients
  if (prior_dist == 1) # normal
    z_beta ~ normal(0, 1);
  else if (prior_dist == 2) # student_t
    z_beta ~ student_t(prior_df, 0, 1);
  /* else prior_dist is 0 and nothing is added */
  
  // Log-prior for intercept  
  if (has_intercept == 1) {
    if (prior_dist_for_intercept == 1) # normal
      gamma ~ normal(prior_mean_for_intercept, prior_scale_for_intercept);
    else if (prior_dist_for_intercept == 2) # student_t
      gamma ~ student_t(prior_df_for_intercept, prior_mean_for_intercept, 
                        prior_scale_for_intercept);
    /* else prior_dist is 0 and nothing is added */
  }
}
generated quantities {
  real alpha[has_intercept];
  real mean_PPD;
  mean_PPD <- 0;
  if (has_intercept == 1)
    alpha[1] <- gamma[1] - dot_product(xbar, beta);
    
  {
    vector[N] eta;
    eta <- X * beta;
    if (has_intercept == 1) eta <- eta + gamma[1];
    if (has_offset) eta <- eta + offset;
    eta <- linkinv_gauss(eta, link);
    for (n in 1:N) mean_PPD <- mean_PPD + normal_rng(eta[n], sigma);
    mean_PPD <- mean_PPD / N;
  }
}
