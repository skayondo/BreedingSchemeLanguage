#'Create a founder population
#'
#'@param sEnv the environment that BSL functions operate in. If NULL, the default \code{simEnv} is attempted
#'@param nInd population size (default:100)
#'@param founderHapsInDiploids set to TRUE if you have uploaded phased diploid data in defineSpecies
#'@param foundersAreInitPop set to TRUE if you want uploaded data to be the breeding population rather than founder haplotypes. This assumes the founders are phased.
#'
#'@seealso \code{\link{defineSpecies}} for an example
#'
#'@return modifies the list sims in environment sEnv by creating a founder population
#'
#'@export
initializePopulation <- function(sEnv=NULL, nInd=100, founderHapsInDiploids=F, foundersAreInitPop=F){
  initializePopulation.func <- function(data, nInd, founderHapsInDiploids){
    seed <- round(stats::runif(1, 0, 1e9))
    md <- data$mapData
    
    geno <- data$founderHaps * 2 - 1
    data$founderHaps <- NULL
    if (foundersAreInitPop){
      nInd <- nrow(geno) %/% 2
      pedigree <- cbind(matrix(-(1:nrow(geno)), ncol=2), 0)
    } else{
      if (!founderHapsInDiploids)
        geno <- geno[sample(nrow(geno), nrow(geno), replace=T),]
      geno <- randomMate(popSize=nInd, geno=geno, pos=md$map$Pos)
      pedigree <- cbind(-geno$pedigree, 0) # For founders, parents will be negative
      colnames(pedigree) <- 1:3
      geno <- geno$progenies
    }
    
    # Genetic effects. This works even if locCov is scalar
    gValue <- calcGenotypicValue(geno=geno, mapData=md)
    covGval <- stats::var(gValue)
    if (any(is.na(covGval)) | sum(diag(covGval)) == 0){
      covGval <- diag(ncol(gValue))
    } else if (Matrix::rankMatrix(covGval) < ncol(gValue)){
      covGval <- diag(diag(covGval))
    }
    coef <- solve(chol(covGval)) %*% chol(data$varParms$locCov)
    md$effects <- md$effects %*% coef
    gValue <- gValue %*% coef
    # Year and location effects: create matrices with zero columns until phenotyped
    locEffects <- matrix(0, nrow=nInd, ncol=0)
    locEffectsI <- matrix(0, nrow=nInd, ncol=0)
    yearEffects <- matrix(0, nrow=nInd, ncol=0)
    yearEffectsI <- matrix(0, nrow=nInd, ncol=0)
    
    genoRec <- data.frame(GID=1:nInd, pedigree=pedigree, popID=0, basePopID=0, hasGeno=FALSE)
    data$mapData <- md
    data$nFounders <- nInd
    data$geno <- geno; data$genoRec <- genoRec; data$gValue <- gValue
    data$locEffects <- locEffects; data$locEffectsI <- locEffectsI
    data$yearEffects <- yearEffects; data$yearEffectsI <- yearEffectsI
    return(data)
  }
  
  if(is.null(sEnv)){
    if(exists("simEnv", .GlobalEnv)){
      sEnv <- get("simEnv", .GlobalEnv)
    } else{
      stop("No simulation environment was passed")
    }
  } 
  parent.env(sEnv) <- environment()
  with(sEnv, {
    if (exists("totalCost")){
      budgetRec <- data.frame(GID=1:nInd, popID=0, hasGeno=FALSE)
    }
    
    if (!onlyCost){
      if(nCore > 1){
        snowfall::sfInit(parallel=T, cpus=nCore)
        sims <- snowfall::sfLapply(sims, initializePopulation.func, nInd=nInd, founderHapsInDiploids=founderHapsInDiploids)
        snowfall::sfStop()
      }else{
        sims <- lapply(sims, initializePopulation.func, nInd=nInd, founderHapsInDiploids=founderHapsInDiploids)
      }
    }
  })
}
