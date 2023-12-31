#' Multi-table correspondence analysis (list of matrices)
#'
#' @param matlist (for \code{corralm_matlist}) list of input matrices; input matrices should be counts (raw or log). Matrices should be aligned row-wise by common features (either by sample or by gene)
#' @param rw_contrib numeric vector, same length as the matlist. Indicates the weight that each dataset should contribute to the row weights. When set to NULL the row weights are *not* combined and each matrix is scaled independently (i.e., using their observed row weights, respectively). When set to a vector of all the same values, this is equivalent to taking the mean. Another option is to the number of observations per matrix to create a weighted mean. Regardless of input scale, row weights for each table must sum to 1 and thus are scaled. When this option is specified (i.e., not `NULL`), the `rtype` argument will automatically be set to `standardized`, and whatever argument is given will be ignored.
#' @inheritParams compsvd
#' @inheritParams corral_preproc
#' 
#' @return When run on a list of matrices, a list with the correspondence analysis matrix decomposition result, with indices corresponding to the concatenated matrices (in order of the list):
#' \describe{
#'     \item{\code{d}}{a vector of the diagonal singular values of the input \code{mat} (from SVD output)}
#'     \item{\code{u}}{a matrix of with the left singular vectors of \code{mat} in the columns (from SVD output)}
#'     \item{\code{v}}{a matrix of with the right singular vectors of \code{mat} in the columns. When cells are in the columns, these are the cell embeddings. (from SVD output)}
#'     \item{\code{eigsum}}{sum of the eigenvalues for calculating percent variance explained}
#' }
#' @rdname corralm
#' @export
#' 
#' @importFrom irlba irlba
#' @importFrom Matrix Matrix rowSums colSums
#' @importClassesFrom Matrix dgCMatrix
#'
#' @examples
#' listofmats <- list(matrix(sample(seq(0,20,1),1000,replace = TRUE),nrow = 25),
#'                    matrix(sample(seq(0,20,1),1000,replace = TRUE),nrow = 25))
#' result <- corralm_matlist(listofmats)
corralm_matlist <- function(matlist, method = c('irl','svd'), ncomp = 30, rtype = c('indexed','standardized','hellinger','freemantukey','pearson'), vst_mth = c('none','sqrt','freemantukey','anscombe'), rw_contrib = NULL, ...){
  method <- match.arg(method, c('irl','svd'))
  rtype <- match.arg(rtype, c('indexed','standardized','hellinger','freemantukey','pearson'))
  vst_mth <- match.arg(vst_mth, c('none','sqrt','freemantukey','anscombe'))
  
  .check_dims(matlist)
  if(is.null(rw_contrib)){
    preproc_mats <- lapply(matlist, corral_preproc, rtype = rtype, vst_mth = vst_mth, ...) 
  }
  else{
    rw_contrib <- .check_rw_contrib(matlist, rw_contrib)
    
    ws <- lapply(matlist, get_weights)
    rwlist <- lapply(ws, '[[', 'row.w')
    row.ws <- Reduce(cbind, rwlist)
    row.ws <- row.ws %*% rw_contrib
    comp_rw <- rowSums(row.ws) / sum(row.ws)
    
    preproc_mats <- lapply(matlist, corral_preproc, rtype = 'standardized', row.w = comp_rw, vst_mth = vst_mth, ...)
    if(rtype != 'standardized'){
      cat('\nSwitched residual type to standardized; using shared row weights.\n')
    }
  }
  concatted <- list2mat(matlist = preproc_mats, direction = 'c')
  result <- compsvd(concatted, method = method, ncomp = ncomp)
  result[['batch_sizes']] <- .batch_sizes(matlist)
  class(result) <- c(class(result),"corralm")
  return(result)
}

#' Multi-table correspondence analysis (SingleCellExperiment)
#'
#' @param sce (for \code{corralm_sce}) SingleCellExperiment; containing the data to be integrated. Default is to use the counts, and to include all of the data in the integration. These can be changed by passing additional arguments. See \code{\link{sce2matlist}} function documentation for list of available parameters.
#' @param splitby character; name of the attribute from \code{colData} that should be used to separate the SCE.
#' @param whichmat character; defaults to \code{counts}, can also use \code{logcounts} or \code{normcounts} if stored in the \code{sce} object
#' @param fullout boolean; whether the function will return the full \code{corralm} output as a list, or a SingleCellExperiment; defaults to SingleCellExperiment (\code{FALSE}). To get back the \code{\link{corralm_matlist}}-style output, set this to \code{TRUE}.
#' @inheritParams compsvd
#' @param ... (additional arguments for methods)
#'
#' @return For SingleCellExperiment input, returns the SCE with embeddings in the reducedDim slot 'corralm' 
#' @rdname corralm
#' @export
#' 
#' @importFrom irlba irlba
#' @importFrom Matrix Matrix rowSums colSums
#' @importFrom SingleCellExperiment reducedDim
#' @importClassesFrom Matrix dgCMatrix
#' @importClassesFrom SingleCellExperiment SingleCellExperiment
#'
#' @examples
#' library(DuoClustering2018)
#' library(SingleCellExperiment)
#' sce <- sce_full_Zhengmix4eq()[1:100,sample(1:3500,100,replace = FALSE)]
#' colData(sce)$Method <- matrix(sample(c('Method1','Method2'),100,replace = TRUE))
#' result <- corralm_sce(sce, splitby = 'Method')
#' 
#' 
corralm_sce <- function(sce, splitby, method = c('irl','svd'), ncomp = 30, whichmat = 'counts', fullout = FALSE, rw_contrib = NULL, ...){
  method <- match.arg(method, c('irl','svd'))
  if(missing(splitby)) {stop('If performing multi-table analysis with a single SCE, the splitby variable must be specified. \nUse corral to analyze as a single table.')}
  mat_list <- sce2matlist(sce, splitby = splitby, whichmat = whichmat)
  svd_output <- corralm_matlist(mat_list, method = method, ncomp = ncomp, rw_contrib = rw_contrib, ...)
  if(fullout){
    class(svd_output) <- c(class(svd_output),'corralm')
    return(svd_output)
  }
  else{
    ind_order <- .indsbysplitby(sce, splitby)
    SingleCellExperiment::reducedDim(sce, 'corralm') <- svd_output$v[ind_order,]
    return(sce)
  }
}

#' Multi-table adaptation of correspondence analysis
#' 
#' This multi-table adaptation of correpondence analysis applies the same scaling technique and enables data alignment by finding a set of embeddings for each dataset within shared latent space.
#' 
#' \code{corralm} is a wrapper for \code{\link{corralm_matlist}} and \code{\link{corralm_sce}}, and can be called on any of the acceptable input types (see \code{inp} below).
#'
#' @param inp list of matrices (any type), a \code{SingleCellExperiment}, list of \code{SingleCellExperiment}s, list of \code{SummarizedExperiment}s, or \code{MultiAssayExperiment}. If using \code{SingleCellExperiment} or \code{SummarizedExperiment}, then include the \code{whichmat} argument to specify which slot to use (defaults to \code{counts}). Additionally, if it is one \code{SingleCellExperiment}, then it is also necessary to include the \code{splitby} argument to specify the batches. For a \code{MultiAssayExperiment}, it will take the intersect of the features across all the assays, and use those to match the matrices; to use a different subset, select desired subsets then call \code{corral}
#' @param whichmat char, when using SingleCellExperiment or other SummarizedExperiment, can be specified. default is 'counts'.
#' @param ... (additional arguments for methods)
#' @inheritParams corralm_matlist
#' @inheritParams corralm_sce
#'
#' @return For a list of \code{\link{SingleCellExperiment}}s, returns a list of the SCEs with the embeddings in the respective \code{reducedDim} slot 'corralm'
#' @rdname corralm
#' @export
#' 
#' @importFrom irlba irlba
#' @importFrom Matrix Matrix rowSums colSums
#' @importFrom methods is
#' @importFrom SingleCellExperiment reducedDim
#' @importFrom MultiAssayExperiment experiments intersectRows assays
#' @importFrom SummarizedExperiment assay
#' @importClassesFrom Matrix dgCMatrix
#' @importClassesFrom SingleCellExperiment SingleCellExperiment
#' @importClassesFrom MultiAssayExperiment MultiAssayExperiment
#'
#' @examples
#' listofmats <- list(matrix(sample(seq(0,20,1),1000,replace = TRUE),nrow = 20),
#'                    matrix(sample(seq(0,20,1),1000,replace = TRUE),nrow = 20))
#' corralm(listofmats)
#' 
#' library(DuoClustering2018)
#' library(SingleCellExperiment)
#' sce <- sce_full_Zhengmix4eq()[seq(1,100,1),sample(seq(1,3500,1),100,replace = FALSE)]
#' colData(sce)$Method <- matrix(sample(c('Method1','Method2'),100,replace = TRUE))
#' result <- corralm(sce, splitby = 'Method')
#' 
corralm <- function(inp, whichmat = 'counts', fullout = FALSE,...){
  if(is(inp,'SingleCellExperiment')){
    corralm_sce(sce = inp, ...)
  }
  else if (is(inp,'ExperimentList')){
    matlist <- as.list(MultiAssayExperiment::assays(MultiAssayExperiment::intersectRows(inp)))
    corralm_matlist(matlist = matlist, ...)
  }
  else if (is(inp,'MultiAssayExperiment')){
    matlist <- as.list(MultiAssayExperiment::assays(MultiAssayExperiment::experiments(MultiAssayExperiment::intersectRows(inp))))
    corralm_matlist(matlist = matlist, ...)
  }
  else if(is(inp,'list') | is(inp,'List')){
    if(all_are(inp,'SingleCellExperiment')){
      matlist <- lapply(inp, SummarizedExperiment::assay, whichmat)
      res <- corralm_matlist(matlist = matlist, ...)
      if(fullout) {
        class(res) <- c(class(res),"corralm")
        return(res)
      }
      else{
        add_embeddings2scelist(scelist = inp, embeddings = res$v) 
      }
    }
    else if (all_are(inp,'SummarizedExperiment')){
      matlist <- lapply(inp, SummarizedExperiment::assay, whichmat)
      corralm_matlist(matlist = matlist, ...)
    }
    else{
      corralm_matlist(matlist = inp, ...) 
    }
  }
}

#' Print method for S3 object corralm
#'
#' @param x (print method) corralm object; the list output from \code{corralm_matlist}
#'
#' @rdname corralm
#'
#' @return .
#' @export
#'
#' @examples
#' # default print method for corralm objects
print.corralm <- function(x,...){
  inp <- x
  pct_var_exp <- inp$pct_var_exp
  ncomp <- length(inp$d)
  cat('corralm output summary==========================================\n')
  cat('  Output "list" includes SVD output (u, d, v) & a table of the\n')
  cat('  dimensions of the input matrices (batch_sizes)\n')
  cat('Variance explained----------------------------------------------\n')
  print(round(pct_var_exp[,seq(1,min(8,ncomp),1)],2))
  cat('\n')
  cat('Dimensions of output elements-----------------------------------\n')
  cat('  Singular values (d) :: ')
  cat(ncomp)
  cat('\n  Left singular vectors (u) :: ')
  cat(dim(inp$u))
  cat('\n  Right singular vectors (v) :: ')
  cat(dim(inp$v))
  cat('\n  See corralm help for details on each output element.')
  cat('\n\n')
  cat('Original batches & sizes (in order)-----------------------------')
  cat('\n ')
  cat(paste0(' ',rownames(inp$batch_sizes),' :: ',inp$batch_sizes[,2],'\n'))
  cat('\n  Use plot_embedding to visualize; see docs for details.\n')
  cat('================================================================\n')
}
