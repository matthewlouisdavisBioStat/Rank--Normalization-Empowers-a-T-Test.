

    ## Below is the code used to perform all differential abundance analyses 
    ## with exception to rank normalization with a t-test
    ## Adapted from https://users.ugent.be/~shawinke/ABrokenPromise/03_diffAbundDetect.html
    
## We want ranks to be applied to non-trimmed data, while this is for DESeq2, LimmaVoom, etc.
simpleTrimGen <- function(obj, minReads = 1, minPrev = 0.05) {
  # `prevalence` is the fraction of samples in which an OTU is observed at
  # least `minReads` times.
  if (class(obj) == "phyloseq") {
    taxRows <- taxa_are_rows(obj)
    if (!taxRows) {
      obj <- t(obj)
    } else {
    }
    otuTab <- as(otu_table(obj), "matrix")
  } else {
    otuTab <- obj
  }  # END - ifelse: obj is *phyloseq* or just *matrix*
  
  prevalence <- rowMeans(otuTab >= minReads)
  indOTUs2Keep <- (prevalence > minPrev) # fix: min prev for small samples is a strictly greater than
  
  if (class(obj) == "phyloseq") {
    obj = prune_taxa(obj, taxa = indOTUs2Keep)
    return(obj)
  } else {
    return(otuTab[indOTUs2Keep, ])
  }
}  # END - function: simpleTrim general





applySimpleTests <- function(physeq, test = c("t-test", "rank", "rankWilcox", "wilcox"), whichOTUs = NULL,
                             groupVar = "group", normFacts = c("doublerank","TMM", "RLE", "GMPR", "ratio", "CSS", "UQ", "none", "SAM", "TSS", "rare", "rank-simple", "wrench", "rank-corrected"), 
                             alt = "two.sided", adjMethod = "BH")
{
  #if(normFacts %!in% c("rank-simple", "rank-corrected")){
    physeq <- simpleTrimGen(physeq)
  #} 
  #physeq <- simpleTrimGen(physeq)
  ### match type of test
  test <- match.arg(test)
  
  ##    ##    ##    ##
  rawcounts <- as(otu_table(physeq), "matrix")
  ##    ##    ##    ##
  
  NFs <- if(normFacts %in% c("none", "rank-simple", "rank-corrected")) 1 else get_variable(physeq, paste("NF", normFacts, sep = "."))
  if(normFacts =="TMM"){
    NFs = NFs * sample_sums(physeq)
  }
  ### select OTUs to analyse
  if (!missing(whichOTUs) || !is.null(whichOTUs))
  {
    physeq <- prune_taxa(taxa_names(physeq)[whichOTUs], x = physeq)
  } else {}
  
  groupBinary <- get_variable(physeq, groupVar)
  groupBinary <- groupBinary == groupBinary[1L]
  
  ##  ##  ##  ##
  counts <- as(otu_table(physeq), "matrix")
  counts <- t(t(counts) / NFs)
  keeprows <- rownames(counts)
  rawcounts <- t(t(rawcounts)/ NFs)
  if(normFacts == "none"){
    ranks <- apply(rawcounts, 2, rank, ties.method = "max")
    ranks <- ranks[keeprows,]
  } else{
    ranks <- apply(counts, 2, rank, ties.method = "max")
  }
  ##  ##  ##  ##
  indg1 <- which(groupBinary == TRUE)
  indg2 <- which(groupBinary == FALSE)
  if(ncol(counts) <= 50){
    exactt = TRUE
  } else{
    exactt = FALSE
  }
  #nonzeroind <- which(rowSums(rawcounts[,indg1]) > 0 & rowSums(rawcounts[,indg2]) > 0)
  switch (test,
          "t-test" = {
            #pVals <- fastT(counts, indg1, indg2)
            pVals = apply(counts, MARGIN = 1L, 
                          function(x, ind) 
                          {Pval=try(t.test(x = x[ind], y = x[!ind], exact = exactt)$p.value, silent=TRUE)
                          if(class(Pval)=="try-error") Pval=1
                          Pval
                          }
                          ,ind = groupBinary)
          },
          "rank" = {
            pVals <- fastT(ranks, indg1, indg2)
          },
          "rankWilcox" = {
            pVals <- apply(ranks, MARGIN = 1L, 
                           function(x, ind) 
                           {Pval=try(wilcox.test(x = x[ind], y = x[!ind], exact = FALSE, 
                                            alternative = alt)$p.value, silent=TRUE)
                           if(class(Pval)=="try-error") Pval=1
                           Pval
                           }
                           ,ind = groupBinary)
          },
          "wilcox" = {
            pVals <- apply(counts, MARGIN = 1L, 
                           function(x, ind) 
                           {Pval=try(wilcox.test(x = x[ind], y = x[!ind], exact = FALSE, 
                                            alternative = alt)$p.value, silent=TRUE)
                           if(class(Pval)=="try-error") Pval=1
                           Pval
                           }
                           ,ind = groupBinary)
          }# END - *wilcox* alternative
  )# END - switch: t-test or Wilcoxon-Mann-Whitney
  pVals <- ifelse(is.nan(pVals), 1, pVals)
  pVals <- ifelse(is.na(pVals), 1, pVals)
  #adjpVals <- rep(1, length(pvals))
  #adjpVals[nonzeroind] <- p.adjust(pVals[nonzeroind], method = adjMethod)
  adjpVals <- p.adjust(pVals, method = adjMethod)
  adjpVals <- ifelse(is.nan(adjpVals), 1, adjpVals)
  adjpVals <- ifelse(is.na(adjpVals), 1, adjpVals)
  
  reject <-  names(adjpVals)[which(adjpVals < .05)]
  
  cor_rej <- sum(reject %in% degenes)
  err_rej <- sum(reject %!in% degenes)
  
  Specificity <- err_rej / ( nrow(otu_table(physeq)) - length(degenes) )
  Sensitivity <- cor_rej / length(degenes)
  FDR <- err_rej / (cor_rej + err_rej)

  res <- matrix(c( test,
                   normFacts,
                   Sensitivity,
                   Specificity,
                   FDR ), nrow = 1)
  colnames(res) <- c( "test",
                      "norm",
                      "sens",
                      "spec",
                      "fdr" )
  
  res[,"fdr"] <- ifelse((res[,"fdr"]) == "NaN", 0, res[,"fdr"])
  res
  
  rawP <- pVals
  list <- list("res" = res,
               "pvals" = rawP)
  list
}# END - function: applyTest





aldexTest <- function(physeq, mc.samples = 128){
  # require(ALDEx2)
  #physeq <- simpleTrimGen(physeq)
  start <- Sys.time()
  if (!taxa_are_rows(physeq)){
    physeq=t(physeq)
  }
  data=data.frame(otu_table(physeq)@.Data)
  res = aldex(data, conditions = sample_data(physeq)$group,mc.samples=mc.samples, test ="t", effect = FALSE)
  Sys.time() - start
  return(res)
}
aldexTTest <- function(res){
  out = cbind(res$we.ep, res$we.eBH)
  colnames(out) = c("rawP","adjP")
  rownames(out) = rownames(res)
  test <- "aldexT"
  reject <-  rownames(out)[which(out[,"adjP"] < .05)]
  cor_rej <- sum(reject %in% degenes)
  err_rej <- sum(reject %!in% degenes)
  Specificity <- err_rej / ( nrow(otu_table(physeq)) -length(degenes) )
  Sensitivity <- cor_rej / length(degenes)
  FDR <- err_rej / (cor_rej + err_rej)
  
  normFacts <- "aldex"
  res <- matrix(c( test,
                   normFacts,
                   Sensitivity,
                   Specificity,
                   FDR ), nrow = 1)
  colnames(res) <- c( "test",
                      "norm",
                      "sens",
                      "spec",
                      "fdr" )
  
  res[,"fdr"] <- ifelse(is.nan(res[,"fdr"]), 0, res[,"fdr"])
  rawP <- out[,"rawP"]
  names(rawP) <- rownames(out)
  list <- list("res" = res,
               "pvals" = rawP)
  return(list)
}

aldexWTest <- function(res){
  out = cbind(res$wi.ep, res$wi.eBH)
  colnames(out) = c("rawP","adjP")
  rownames(out) = rownames(res)
  test <- "aldexW"
  reject <-  rownames(out)[which(out[,"adjP"] < .05)]
  cor_rej <- sum(reject %in% degenes)
  err_rej <- sum(reject %!in% degenes)
  Specificity <- err_rej / ( nrow(otu_table(physeq)) -length(degenes) )
  Sensitivity <- cor_rej / length(degenes)
  FDR <- err_rej / (cor_rej + err_rej)
  
  normFacts <- "aldex"
  res <- matrix(c( test,
                   normFacts,
                   Sensitivity,
                   Specificity,
                   FDR ), nrow = 1)
  colnames(res) <- c( "test",
                      "norm",
                      "sens",
                      "spec",
                      "fdr" )
  
  res[,"fdr"] <- ifelse(is.nan(res[,"fdr"]), 0, res[,"fdr"])
  rawP <- out[,"rawP"]
  names(rawP) <- rownames(out)
  list <- list("res" = res,
               "pvals" = rawP)
  return(list)
}

### Perform EdgeR, robust version for overdispersion estimation.
### edgeR_QLFTest_robust_3.6.4
#   function (counts, group, design = NULL, mc.cores = 4, prior.df = 10) 
edgeRRobust <- function(physeq, design = as.formula("~ group"), prior.df = 10, 
                        normFacts = c("doublerank","TMM", "RLE", "GMPR", "ratio", "CSS", "UQ", "none", "SAM", "TSS", "rank"), returnDispEsts = FALSE)
{
  physeq <- simpleTrimGen(physeq)
  groupVar <- get_variable(physeq, "group")
  counts <- as(otu_table(physeq), "matrix")
  if( normFacts=="TSS"){
    NFs = 1
  } else {
    normFacts <- paste("NF", normFacts, sep = ".")
    NFs = get_variable(physeq, normFacts)
    NFs = NFs/exp(mean(log(NFs)))
  }
  
  dge <- DGEList(counts = counts, group = groupVar) #, remove.zeros=TRUE)
  dge$samples$norm.factors <- NFs
  desMat <- model.matrix(design, data.frame(sample_data(physeq)))
  dgeW <- estimateGLMRobustDisp(y = dge, design = desMat, prior.df = prior.df, maxit = 6)
  glmFit <- glmQLFit(y = dgeW, dispersion = dgeW$tagwise.dispersion, robust = TRUE,
                     design = desMat)
  glmRes <- glmQLFTest(glmFit, coef = 2)
  pval <- glmRes$table$PValue
  padj <- p.adjust(pval, "BH")
  
  out <- cbind("rawP" = pval, "adjP" = padj)
  rownames(out) = taxa_names(physeq)
  
  test <- "edgeR"
  reject <-  rownames(out)[which(out[,"adjP"] < .05)]
  
  cor_rej <- sum(reject %in% degenes)
  err_rej <- sum(reject %!in% degenes)
  Specificity <- err_rej / ( nrow(otu_table(physeq)) -length(degenes) )
  Sensitivity <- cor_rej / length(degenes)
  FDR <- err_rej / (cor_rej + err_rej)
  normFacts <- ifelse(substr(normFacts, 1, 2) == "NF",
                     substr(normFacts, 4, nchar(as.character(normFacts))),
                     normFacts)
  res <- matrix(c( test,
                   normFacts,
                   Sensitivity,
                   Specificity,
                   FDR ), nrow = 1)
  colnames(res) <- c( "test",
                      "norm",
                      "sens",
                      "spec",
                      "fdr" )
  
  res[,"fdr"] <- ifelse(is.nan(res[,"fdr"]), 0, res[,"fdr"])
  rawP <- out[,"rawP"]
  names(rawP) <- rownames(out)
  list <- list("res" = res,
               "pvals" = rawP)
  list
}# END: edgeRRobust

### performs negative binomial two-sample test of *DESeq2* to detect Diff. Abund.
DESeq2 <- function(physeq, design = as.formula("~ group"), IndepFilter = NULL,
                             normFacts = c("doublerank","TMM", "RLE", "GMPR", "ratio", "CSS", "UQ", "none", "SAM", "TSS", "rank"), returnDispEsts = FALSE, use_ranks = FALSE)
{
  
  ## Full example using DESeq2
  physeq <- simpleTrimGen(physeq)
  counts2 <- as(otu_table(physeq), "matrix")
  counts2 <- round(counts2) # to account for the 'ties' present in ranks 
  groupVar <- "group"
  group <- c(get_variable(physeq, groupVar))
  design <- model.matrix(~group)
  geoMeans <- apply(counts2, 
                    1, 
                    function(row) if (all(row == 0)) 0 else exp(mean(log(row[row != 0]))))
  dds <- DESeqDataSetFromMatrix(
    countData = counts2,
    colData = as.data.frame(group),
    design = design)
  if(use_ranks == TRUE){
    sizeFactors(dds) <- rep(1, ncol(counts2))
  } else if(normFacts == "GMPR"){
    sizeFactors(dds) <- get_variable(physeq, paste("NF", normFacts, sep = "."))
  } else{
    dds <- estimateSizeFactors(dds, geoMeans = geoMeans)
  }
  dds <- DESeq(dds)
  res <- results(dds)
  out <- as.matrix(res[, c("pvalue", "padj")])
  colnames(out) <- c("rawP", "adjP")
  
  out[, "adjP"] <- ifelse(is.na(out[,"adjP"]), 1, out)
  
  
  
  test <- "DESeq2"
  reject <-  rownames(out)[which(out[,"adjP"] < .05)]
  
  cor_rej <- sum(reject %in% degenes)
  err_rej <- sum(reject %!in% degenes)
  Specificity <- err_rej / ( nrow(otu_table(physeq)) -length(degenes) )
  Sensitivity <- cor_rej / length(degenes)
  FDR <- err_rej / (cor_rej + err_rej)
  
  normFacts <- ifelse(substr(normFacts, 1, 2) == "NF",
                      substr(normFacts, 4, nchar(as.character(normFacts))),
                      normFacts)
  res <- matrix(c( test,
                   normFacts,
                   Sensitivity,
                   Specificity,
                   FDR ), nrow = 1)
  colnames(res) <- c( "test",
                      "norm",
                      "sens",
                      "spec",
                      "fdr" )
  
  res[,"fdr"] <- ifelse(is.nan(res[,"fdr"]), 0, res[,"fdr"])
  rawP <- out[,"rawP"]
  names(rawP) <- rownames(out)
  list <- list("res" = res,
               "pvals" = rawP)
  list
}
  
  
### Performs Limma-Voom, robust version for eBayes fit
limmaVoomRobust <- function (physeq, design = as.formula("~ group"), 
                             normFacts = c("doublerank","TMM", "RLE", "GMPR", "ratio", "CSS", "UQ", "none", "SAM", "TSS", "rank", "quantile"))
{
  
  physeq <- simpleTrimGen(physeq)
  ## group variable
  groupVar <- get_variable(physeq, "group")
  ## OTU table
  counts <- as(otu_table(physeq), "matrix")
  ## extract chosen Normalisation Factors
  normFacts <- paste("NF", normFacts, sep = ".")
  NFs <- get_variable(physeq, normFacts)
  if(normFacts == "NF.TMM"){
    NFs = NFs *sample_sums(physeq)
  }
  
  ## add in unique quantile normalization
  if(normFacts == "quantile"){
    counts <- limma::normalizeBetweenArrays(otuTab)
  }
  ## design matrix
  desMat <- model.matrix(as.formula(design), data = data.frame(sample_data(physeq)))
  
  voomRes <- voom(counts = counts, design = desMat, plot = FALSE, lib.size = NFs)
  fitRes <- lmFit(object = voomRes, design = desMat)
  fitRes <- eBayes(fitRes, robust = TRUE)
  pval <- topTable(fitRes, coef = 2, n = nrow(counts), sort.by = "none")$P.Value
  padj <- topTable(fitRes, coef = 2, n = nrow(counts), sort.by = "none")$adj.P.Val
  out = cbind("rawP" = pval, "adjP" = padj)
  rownames(out)= taxa_names(physeq)
  
  
  test <- "Voom"
  reject <-  rownames(out)[which(out[,"adjP"] < .05)]
  
  cor_rej <- sum(reject %in% degenes)
  err_rej <- sum(reject %!in% degenes)
  Specificity <- err_rej / ( nrow(otu_table(physeq)) -length(degenes) )
  Sensitivity <- cor_rej / length(degenes)
  FDR <- err_rej / (cor_rej + err_rej)
  
  normFacts <- ifelse(substr(normFacts, 1, 2) == "NF",
                      substr(normFacts, 4, nchar(as.character(normFacts))),
                      normFacts)
  res <- matrix(c( test,
                   normFacts,
                   Sensitivity,
                   Specificity,
                   FDR ), nrow = 1)
  colnames(res) <- c( "test",
                      "norm",
                      "sens",
                      "spec",
                      "fdr" )
  
  res[,"fdr"] <- ifelse(is.nan(res[,"fdr"]), 0, res[,"fdr"])
  rawP <- out[,"rawP"]
  names(rawP) <- rownames(out)
  list <- list("res" = res,
               "pvals" = rawP)
  list
}# END: limmaVoomRobust


### Perform ZIG regression from metagenomeSeq
metagenomeSeqZIG <- function (physeq, design = as.formula("~ group"), 
                              normFacts = c("doublerank","TMM", "RLE", "GMPR", "ratio", "CSS", "UQ", "none", "SAM", "TSS", "wrench"))
{
  # require(metagenomeSeq)
  ### force orientation OTUs x samples
  physeq <- simpleTrimGen(physeq)
  if (!taxa_are_rows(physeq))
  {
    physeq <- t(physeq)
  } else {}
  
  ## OTU table
  otuTab <- as(otu_table(physeq), "matrix")
  ## sample data converted to Annotated Data Frame
  ADF <- AnnotatedDataFrame(data.frame(sample_data(physeq)))
  ## design matrix
  desMat <- model.matrix(as.formula(design), data = data.frame(sample_data(physeq)))
  ## extract the chosen Normalisation Factors
  normFacts <- paste("NF", normFacts, sep = ".")
  NFs <- get_variable(physeq, normFacts)
  if(normFacts == "NF.TMM"){
    NFs = NFs *sample_sums(physeq)
  }
  if (all(NFs==1))
  {
    ## needs one normalisation factor, library size in this case
    MGS <- newMRexperiment(counts = otuTab, phenoData = ADF, 
                           normFactors = colSums(otuTab))
  } else
  {
    MGS <- newMRexperiment(counts = otuTab, phenoData = ADF, normFactors = NFs)
  }# END - ifelse: normalisation factors all 1 or not
  
  suppressWarnings(fit <- try(fitZig(MGS, desMat), silent = TRUE))
  
  if(class(fit)=="try-error"){
    res=matrix(NA, ncol=2, nrow=ntaxa(physeq))
  }else{
    # You need to specify all OTUs to get the full table from MRfulltable. 
    res <- MRfulltable(fit, number = nrow(get("counts", assayData(MGS))))
    # if any OTUs left out, rm those from x. Detected by NA rownames.
    res <- res[!is.na(rownames(res)), c("pvalues", "adjPvalues"), drop = FALSE]}
  colnames(res) <- c("rawP", "adjP")
  rawP <- res[,"rawP"]
  names(rawP) <- rownames(res)
  test <- "metagenomeSeq"
  reject <-  rownames(res)[which(res[,"adjP"] < .05)]
  cor_rej <- sum(is.element(reject, degenes))
  err_rej <- sum(!is.element(reject, degenes))
  Specificity <- err_rej / ( nrow(otu_table(physeq)) -length(degenes) )
  Sensitivity <- cor_rej / length(degenes)
  FDR <- err_rej / (cor_rej + err_rej)
  
  normFacts <- ifelse(substr(normFacts, 1, 2) == "NF",
                      substr(normFacts, 4, nchar(as.character(normFacts))),
                      normFacts)
  res <- matrix(c( test,
                   normFacts,
                   Sensitivity,
                   Specificity,
                   FDR ), nrow = 1)
  colnames(res) <- c( "test",
                      "norm",
                      "sens",
                      "spec",
                      "fdr" )
  
  res[,"fdr"] <- ifelse(is.nan(res[,"fdr"]), 0, res[,"fdr"])
  list <- list("res" = res,
               "pvals" = rawP)
  list
}# END - function: metagenomeSeqZIG
# 



## Matt's permutation test
permTest <- function(    otu_table,    # rows as taxa, columns as samples
                         ncores = 8, # number of cores used
                         N = 1000,   # number of permutations
                         indg1,      # column indices of group 1
                         indg2,      # column indices of group 2
                         alpha = 0.05, # significance level 
                         adj = "",   # BH? FDR? what kind of adjustment, if any
                         makeCluster = T, # if we should make a cluster within the function
                         juststat = FALSE){ # return only the permuted t-statistics
  ## Observed T-Statistic
  l1 <- length(indg1)
  l2 <- length(indg2)
  S1 <- (rowSums((otu_table[,indg1] - rowMeans(otu_table[,indg1]))^2) / (l1 - 1))
  S2 <- (rowSums((otu_table[,indg2] - rowMeans(otu_table[,indg2]))^2) / (l2 - 1))
  sigmas <- sqrt ( S1/l1 + S2/l2 )
  TObs <- (rowMeans(otu_table[,indg1]) - rowMeans(otu_table[,indg2])) / sigmas
  TObs <- ifelse(is.nan(TObs), 0, TObs)
  
  ## Run in Parallel
  ncol <- ncol(otu_table)
  if(makeCluster){
    cl <- makeCluster(ncores)
    doSNOW::registerDoSNOW(cl)
  }
  TPerm <- foreach(i = 1:N, .combine = "cbind") %dopar% {
    ## Permute Column Labels
    otu_tablePerm <- otu_table[,sample(1:ncol, ncol, replace = FALSE)]
    ## Recalc Statistic
    S1 <- (rowSums((otu_tablePerm[,indg1] - rowMeans(otu_tablePerm[,indg1]))^2) / (l1 - 1))
    S2 <- (rowSums((otu_tablePerm[,indg2] - rowMeans(otu_tablePerm[,indg2]))^2) / (l2 - 1))
    sigmas <- sqrt ( S1/l1 + S2/l2 )
    TP <- (rowMeans(otu_tablePerm[,indg1]) - rowMeans(otu_tablePerm[,indg2])) / sigmas
    ifelse(is.nan(TP), 0, TP)
  }
  if(makeCluster){
    stopCluster(cl)
  }
  if(juststat == TRUE){
    return(TPerm)
  }
  
  if(adj == "BH"){
    ## BH correction for pvalues 
    return(rownames(TPerm)[which(p.adjust(rowMeans(abs(TPerm) > abs(TObs)),"BH") <= alpha)])
  } else if(adj == "fdr"){
    ## FDR stepdown correction procedure for controlling pvalues
    cs <- runif(1000,0,max(abs(TObs)))
    fdrs <- rep(NA, 1000)
    names(fdrs) <- cs
    if(makeCluster){
      cl <- makeCluster(4)
      doSNOW::registerDoSNOW(cl)
    }
    fdrs <- foreach(i = 1:length(cs),.combine = "c") %do% {
      c <- cs[i]
      R <- sum(abs(TObs) >= c)
      W <- mean(colSums(TPerm >= c))
      W/R
    }
    if(makeCluster){
      stopCluster(cl)
    }
    diff <- abs(fdrs - alpha)
    names(diff) <- cs
    C <- unique(as.numeric(names(diff)[which(diff == min(diff, na.rm = TRUE))]))[1]
    ## rejections
    return(names(TObs)[which(abs(TObs) > abs(C))])
  } else{
    ## Return raw pvalues otherwise
    return(rowMeans(abs(TPerm) > abs(TObs)))
  }
  
}
