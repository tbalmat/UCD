#####################################################################################################
# Duke University UCD Shiny App, Feb 2020
# Shiny server script
#####################################################################################################

# Information on shiny and visnetwork available at:
# https://shiny.rstudio.com/
# https://github.com/rstudio/shiny
# https://cran.r-project.org/web/packages/shiny/shiny.pdf
# https://cran.r-project.org/web/packages/visnetwork/visnetwork.pdf

#####################################################################################################
# Data source:  UCD database developed by University of Nebraska and Duke University
#####################################################################################################

options(max.print=1000)      # number of elements, not rows
options(stringsAsFactors=F)
options(scipen=999999)
#options(device="windows")

library(shiny)
library(visNetwork)
library(RNeo4j)
library(DT)

##########################################################################################################
# Set static filter and appearance parameters
##########################################################################################################

# Vertex colors (one each for concepts, participant features, prescriptions, and role groups)
vc1 <- "#FFEE66"
vc2 <- "#66AAFF"
vc3 <- "#88AAAA"
vc4 <- "#DDBBBB"


# Edge colors
ec1 <- "#080808"
ec2 <- "#C02020"

# Vertex and edge font sizes
vfsz <- 12
efsz <- 12

# Font stroke (outline) color
fsc1 <- "#909090"

##########################################################################################################
# Connect to DB
##########################################################################################################

dbcon <- startGraph(c("http://localhost:7474/db/data/", "http://localhost:7479/db/data/")[1],
                    username="neo4j",
                    password=c("neo4j01", "Duke123!")[1])

##########################################################################################################
# Function to assemble graph components (vertices and edges)
##########################################################################################################

assembleNetComponents <- function(pConcept, nodeVar1, nodeVar2, vColor1, vColor2, nedgemin,
                                  eopacity, vmassf, vsizefactor, vfontsz, vfontcolor, elabVar, accMethod) {

  #print(nodeVar1)
  #print(nodeVar2)
  #print(colnames(pConcept))
  #print(pConcept)

  # Compose graph data set, with participant groups and concepts as vertices and relationship of
  # participant property and concept as edges
  # Parameters:
  # pConcept ...... a data frame with one row per participant, concept/prescription combination
  # nodeVar1 ...... name of pConcept column from which to construct the first set of vertices
  # nodeVar2 ...... name of pConcept column from which to construct the second set of vertices
  # vColorX ....... color to assign vertex set x
  # nedgemin ...... restrict edges to those with a minimum of this frequency
  # eopacity ...... edge opacity
  # vmassf ........ vertex mass factor, used in physics computations, low -> tighter graph
  # vsizefactor ... vertex rendering scale factor
  # vfontsize ..... vertex label font size (two position vector, one for each vertex set)
  # vfontcolor .... vertex label font color (two position vector, one for each vertex set)
  # elabVar ....... pConcept vector to include in edge labels
  # accMethod ..... method used to accumulate node and vertex observation frequencies
  #                 possible values are:
  #                 PID ............ count unique participant IDs for v1 frequencies
  #                                  count unique participant IDs for v2 frequencies
  #                                  count intersection of unique v1, v2 participant IDs for edge frequencies
  #                 V1PIDV2nEn ..... count unique participant IDs for v1 frequencies
  #                                  accumulate n by nodeVar2 values for v2 frequencies
  #                                  accumulate n by nodeVar1, nodeVar2 combinations for edge frequencies
  #                 V1PIDV2PIDEn ... count unique participant IDs for v1 frequencies
  #                                  count unique participant IDs for v2 frequencies
  #                                  count unique participant ID, nodeVar2 values for edge frequencies

  # Note the existence of column n in pConcept
  # This indicates the frequency of pairs of observations for each nodeVar1, nodeVar2 combination (row)

  if(nrow(pConcept)>0) {
    # Tabulate vertices
    # Vertex set v1 corresponds to nodeVar1, set v2 to nodeVar2
    # If accMethod is unrecognized then frequencies for unique values of nodeVar1 and nodeVar2 are accumulated
    v1 <- aggregate(1:nrow(pConcept), by=list(rep(nodeVar1, nrow(pConcept)), pConcept[,nodeVar1]),
                    function(k)
                      if(tolower(accMethod) %in% c("pid", "v1pidv2nen", "v1pidv2piden")) {
                        length(unique(pConcept[k,"participantID"]))
                      } else {
                        length
                      })
    colnames(v1) <- c("nodeVar", "lab", "n")
    v2 <- aggregate(1:nrow(pConcept), by=list(rep(nodeVar2, nrow(pConcept)), pConcept[,nodeVar2]),
                    function(k)
                      if(tolower(accMethod) %in% c("pid", "v1pidv2piden")) {
                        length(unique(pConcept[k,"participantID"]))
                      } else if(tolower(accMethod)=="v1pidv2nen") {
                        sum(pConcept[k,"n"])
                      } else {
                        length
                      })
    colnames(v2) <- c("nodeVar", "lab", "n")
    #print(v1)
    #print(v2)

    # Tabulate edges by nodeVar1, nodeVar2 combinations
    # If accMethod is unrecognized then frequencies of unique nodeVar1, nodeVar2 values are accumulated
    if(!is.na(elabVar)) {
      agglist <- list(pConcept[,nodeVar1], pConcept[,elabVar], pConcept[,nodeVar2])
      cname <- c("v1", "edge", "v2", "n")
    } else {
      agglist <- list(pConcept[,nodeVar1], pConcept[,nodeVar2])
      cname <- c("v1", "v2", "n")
    }
    edat <- aggregate(1:nrow(pConcept), by=agglist,
                      function(k)
                        if(tolower(accMethod)=="pid") {
                          length(unique(pConcept[k,"participantID"]))
                        } else if(tolower(accMethod) %in% c("v1pidv2piden", "v1pidv2nen")) {
                          sum(pConcept[k,"n"])
                        } else {
                          length
                        })
    colnames(edat) <- cname
    #print(edat)
    # Filter edges by frequency
    edat <- subset(edat, n>=nedgemin)
    if(nrow(edat)>0) {
      # Retain vertices on remaining edges
      v1 <- subset(v1, lab %in% edat[,"v1"])
      v2 <- subset(v2, lab %in% edat[,"v2"])
      if(!is.na(elabVar)) {
        edat[,"hovtext"] <- paste(edat[,"v1"], "; ", edat[,"edge"], "; ", edat[,"v2"], "; n = ", edat[,"n"], sep="")
      } else {
        edat[,"hovtext"] <- paste(edat[,"v1"], "; ", edat[,"v2"], "; n = ", edat[,"n"], sep="")
      }
      vset <- c(rep(1, nrow(v1)), rep(2, nrow(v2)))
      vertex0 <- data.frame("set"=vset,
                            "v"=c(v1[,"lab"], v2[,"lab"]),
                            "vColor"=c(vColor1, vColor2)[vset],
                            "lab"=c(v1[,"lab"], v2[,"lab"]),
                            "vfontcolor"=vfontcolor[vset],
                            "vfontsz"=vfontsz[vset],
                            "vfstroke"=ifelse(vfontcolor[vset]<"#CCCCCC", fsc1, "#404040"),
                            "n"=c(v1[,"n"], v2[,"n"]),
                            "hovtext"=c(paste(v1[,"lab"], "; n = ", v1[,"n"], sep=""),
                                        paste(v2[,"lab"], "; n = ", v2[,"n"], sep="")),
                            "varID"=c(v1[,"nodeVar"], v2[,"nodeVar"]))
    } else {
      vertex0 <- data.frame()
    }
  } else {
    vertex0 <- data.frame()
  }

  #print(vertex0)

  # Compose vertex and edge sets
  if(nrow(vertex0)>0) {
    # Vertices
    vertex <- data.frame("id"=1:(nrow(vertex0)),
                         "fixed"=F,
                         "label"=vertex0[,"v"],
                         "color"=vertex0[,"vColor"],
                         # Font size scaled to node observation frequency seems like agood idea, but introduces distracting variation
                         #"font"=list("color"=vtcolor, "size"=vfontsz[vertex0[,"set"]]*10*vertex0[,"n"]/max(vertex0[,"n"]), strokeWidth=1, "strokeColor"=fsc1),
                         "font"=list("color"=vertex0[,"vfontcolor"], "size"=vertex0[,"vfontsz"], strokeWidth=1, "strokeColor"=vertex0[,"vfstroke"]),
                         "value"=vsizefactor*vertex0[,"n"],
                         "mass"=vmassf*(5+vertex0[,"n"]),
                         "title"=vertex0[,"hovtext"],
                         "varID"=vertex0[,"varID"])
    #print(vertex)
    # Include groups for legend configuration
    vertex[,"group"] <- c(nodeVar1, nodeVar2)[vertex0[,"set"]]
    #print(vertex)
    rownames(vertex) <- NULL
    # Compose vertex IDs (they are required for unambiguous identification in edge construction)
    vid <-setNames(vertex[,"id"], vertex[,"label"])
    #print(colnames(edat))
    # Compose edges
    if(nrow(edat)>0) {
      edge <- data.frame("from"=vid[edat[,"v1"]],
                         "to"=vid[edat[,"v2"]],
                         # Width
                         value=edat[,"n"],
                         #"label"=paste("n = ", edat[,"lab"], sep=""), 
                         # Hover text
                         "title"=edat[,"hovtext"],
                         "hoverWidth"=0,
                         "selectionWidth"=0,
                         "color"=list("color"=ec1, "opacity"=eopacity, "highlight"=ec2),
                         # Font size scaled to node observation frequency seems like agood idea, but introduces distracting variation
                         #"font"=list("color"="white", "size"=vfontsz[1]*10*vertex0[match(vid[edat[,"v1"]], vertex[,"id"]),"n"]/max(vertex0[,"n"]), strokeWidth=1, "strokeColor"=fsc1),
                         "font"=list("color"="white", "size"=vfontsz[1], strokeWidth=1, "strokeColor"=fsc1),
                         #"length"=20,
                         "physics"=T,
                         "smooth"=T)
    } else {
      edge <- data.frame()
    }

  } else {
    vertex <- data.frame()
    edge <- data.frame()
  }

  print("net assembled")
  return(list("vertex"=vertex, "edge"=edge))

}

##########################################################################################################
# Function to append nodes and edges defined in netComponents2 to those in netComponents1
# Edges are composed by identifying node positions in appended set to those of edges defined in sets 1 and 2
# Properties of set 2 nodes in appended set are taken from set 2
##########################################################################################################

appendNetwork <- function(netComponents1, netComponents2) {

  # Append set 2 nodes to set 1
  # Limit to nodes that do not already appear in set 1
  vertex <- netComponents1[["vertex"]]
  n1 <- nrow(vertex)
  k <- which(!netComponents2[["vertex"]][,"label"] %in% vertex[,"label"])
  #print(k)
  if(length(k)>0) {
    vertex[(n1+1):(n1+length(k)),] <- netComponents2[["vertex"]][k,]
    rownames(vertex) <- NULL
    # Revise node IDs of appended vertices to position in appended set
    vertex[(n1+1):(n1+length(k)),"id"] <- (n1+1):(n1+length(k))
    #print(vertex)
  }

  # Append edges
  edge <- netComponents1[["edge"]]
  n2 <- nrow(netComponents2[["edge"]])
  if(n2>0) {
    n1 <- nrow(edge)
    edge[(n1+1):(n1+n2),] <- netComponents2[["edge"]]
    rownames(edge) <- NULL
    # Realign appended node IDs so that source corresponds to source in set 1 and destination corresponds
    # to those of newly appended nodes
    # Retrieve source and destination vertex labels
    vFrom <- netComponents2[["vertex"]][netComponents2[["edge"]][,"from"],"label"]
    vTo <- netComponents2[["vertex"]][netComponents2[["edge"]][,"to"],"label"]
    # Revise IDs of appended edge vertices using positions of source and dest labels in appended node set
    edge[(n1+1):(n1+n2),"from"] <- vertex[match(vFrom, vertex[,"label"]),"id"]
    edge[(n1+1):(n1+n2),"to"] <- vertex[match(vTo, vertex[,"label"]),"id"]
  }

  return(list("vertex"=vertex, "edge"=edge))

}

##########################################################################################################
# Function to compose renderable graph using visNetwork() functions
# Notes:
# 1. Groups are character values assigned to vertex sets in assembleNetwork
# 2. Color parameters affect legend appearance and should agree with those used in vertex assembly
##########################################################################################################

composeNetwork <- function(vertex, edge, nodeVar1, nodeVar2, nodeVar3=NA, nodeVar4=NA,
                           vColor1, vColor2, vColor3, vColor4,
                           nCluster, nearestHighlightDeg) {

  g <- visNetwork(vertex, edge) %>% 
         visGroups(groupname=nodeVar1, color=vColor1, font=list("color"=ifelse(vColor1<"#AAAAAA", "white", "#202020"), "size"=12)) %>%
         visGroups(groupname=nodeVar2, color=vColor2, font=list("color"=ifelse(vColor2<"#AAAAAA", "white", "#202020"), "size"=12))

  # Include third set of nodes, if specified
  if(!is.na(nodeVar3))
    g <- g %>% visGroups(groupname=nodeVar3, color=vColor3, font=list("color"=ifelse(vColor3<"#AAAAAA", "white", "#202020"), "size"=12))

  # Include fourth set of nodes, if specified
  if(!is.na(nodeVar4))
    g <- g %>% visGroups(groupname=nodeVar4, color=vColor4, font=list("color"=ifelse(vColor4<"#AAAAAA", "white", "#202020"), "size"=12))

  # Continue with composition
  g <- g %>%
         visLayout(randomSeed=1) %>%
         visLegend(useGroups=T, position="right", width=0.1, zoom=F) %>%
         visOptions(highlightNearest=list("enabled"=T, degree=nearestHighlightDeg, "hover"=T),
                    nodesIdSelection=T, selectedBy=list(variable="group", multiple=T), collapse=T) %>%
         visInteraction(hover=T, hoverConnectedEdges=T, navigationButtons=F) %>%
         #visHierarchicalLayout(direction="LR") %>%
         visPhysics(timestep=0.25, minVelocity=10, maxVelocity=50, 
                    barnesHut=list("avoidOverlap"=0.5, "springLength"=200, "springConstant"=0.5, "damping"=0.5),
                    repulsion=list("nodeDistance"=-500),
                    stabilization=list("enabled"=T, "iterations"=1000)) %>%
         # Enclose java functions in {} brackets, otherwise they hang with no message 
         #visEvents(type="once", startStabilizing="function() {
         #                                           alert('begin stabilization')
         #                                         }") %>%
         visEvents(type="once", stabilized="function() {
                                              //alert('stab')
                                              Shiny.onInputChange('stabilized', '0')
                                            }") %>%
         # Trigger shiny events using mouse clicks with shift and ctl keys
         # Double click events fire two click events, so use shift-click for doubles
         # The following (java) instructions cause changes to input$shiftClick and input$ctlClick
         # See the corresponding event handlers for additional info
         visEvents(type="on", click="function(obj) {
                                       if(obj.event.srcEvent.shiftKey) {
                                         //alert('shift-click')
                                         Shiny.onInputChange('shiftClick', obj)
                                       } else if(obj.event.srcEvent.altKey) {
                                         //alert('alt-click')
                                         Shiny.onInputChange('altClick', obj)
                                       } else {
                                         //alert('click')
                                         Shiny.onInputChange('click', obj)
                                       }
                                     }")
         #visEvents(type="on", doubleClick="function(obj) Shiny.onInputChange('doubleClick', obj)")

  # Cluster, if requested
  if(nCluster>0)
    g <- g %>% visClusteringByHubsize(size=nCluster)

  print("net composed")
  return(g)

}

##########################################################################################################
# Query participant and concept UCD observations using requested parameter values
# Return list of data frames containing vertex and edge configurations
##########################################################################################################

queryAndConstructGraphPC <- function(nodeVar1, nodeVar2, conceptID, vColor1, vColor2, nedgemin, eopacity,
                                     vMassFactor, vSizeFactor, vFontSize, elabVar, accMethod) {
 
  # Retrieve node and edge data for participants connected to the specified concept
  # Note the specification of directed edges although, in the db, they are limited to participant->concept
  # Also note the retrieval of unique combinations of participant and concept to avoid bias due to duplicate observations 
  # Although various types of concept nodes (ie, labels ["ObjectConcept", "Neuro", "Psych"], ["ObjectConcept", "Psych"])
  # are related to the terminating concept identified here by z.sctid (relationship type ISA), all (observed) ISA
  # relationships from participants to concept nodes with an ISA relation to the terminating concept are of type
  # ["ObjectConcept", "Psych", "PPsych", "PSCT"]
  # All relationships from participants to concepts are of type P_SCT
  query <- paste(" match(x:Participant)-[:P_SCT]->(y:ObjectConcept)-[r:ISA*]->(z:ObjectConcept)",
                 " where z.sctid='", conceptID, "' and y.active='1' and z.active='1'",
                 " with",
                 " case when(labels(x)=['Participant'])then 'UCDDist'",
                 "      when(labels(x)=['Participant','UCD_Proximal'])then 'UCDProx'",
                 " end as UCDProxDist,",
                 " x.ParticipantId as participantID, x.Sex as Sex, x.UCDDx as UCDDx,",
                 " case when(toInteger(x.OnsetAgeDays)<11)then '0-11'",
                 "      when(toInteger(x.OnsetAgeDays)<101)then '11-100'",
                 "      when(toInteger(x.OnsetAgeDays)<1001)then '101-1000'",
                 "      when(toInteger(x.OnsetAgeDays)<10001)then '1001-10000'",
                 "      when(toInteger(x.OnsetAgeDays) is not null)then '>10000'",
                 "      else null",
                 " end as onsetAgeDays,",
                 " startNode(last(r)) as concept",
                 " return  UCDProxDist, participantID, Sex, UCDDx, onsetAgeDays,",
                 "         concept.sctid as conceptID, labels(concept) as conceptLabel,",
                 "         concept.FSN as FSN, count(1) as n", sep="")

  pConcept <- cypher(dbcon, query)

  # Relabel null values
  pConcept[which(is.na(pConcept[,"Sex"])),"Sex"] <- "na"
  pConcept[which(is.na(pConcept[,"UCDDx"])),"UCDDx"] <- "na"
  pConcept[which(is.na(pConcept[,"onsetAgeDays"])),"onsetAgeDays"] <- "na"

  # Assemble concept and participant nodes and edges
  # Return in two element list with names "vertex" and "edge"
  return(assembleNetComponents(pConcept=pConcept,
                               nodeVar1=nodeVar1,
                               nodeVar2=nodeVar2,
                               vColor1=vColor1,
                               vColor2=vColor2,
                               nedgemin=nedgemin,
                               eopacity=eopacity,
                               vmassf=vMassFactor,
                               vsizefactor=vSizeFactor,
                               vfontsz=c(vFontSize, 0.8*vFontSize),
                               # Adjust font color light for dark vertex color, dark for light
                               vfontcolor=c(ifelse(vColor1<"#CCCCCC", vColor1, "#404040"),
                                            ifelse(vColor2<"#CCCCCC", vColor2, "#404040")),
                               elabVar=elabVar,
                               accMethod=accMethod))

}

##########################################################################################################
# Query prescription and (participant or concept) UCD observations using requested parameter values
# Return list of data frames containing vertex and edge configurations
# Parameter subsume (T/F) enables prescriptions to be combined into parent nodes based on RxNorm relationships
##########################################################################################################

queryAndConstructGraphPrescrip <- function(nodeVar1, conceptID, subsume, vColor1, vColor2, nedgemin,
                                           eopacity, vMassFactor, vSizeFactor, vFontSize, elabVar, accMethod) {

  # Retrieve node and edge data for prescriptions connected to participants connected to the specified concept
  # Note the specification of directed edges although, in the db, they are limited to participant->rx
  # Also, the participant node appears between P_RX and P_SCT because it has such relationships to RX and ObjectConcept
  # The query match(w:Participant)-[:P_RX]->(x:RXCUI)-[:P_SCT]->(y:ObjectConcept) returns null because RX has no
  # relationships directed to ObjectConcept
  # All relationships from participants to prescriptions are of type P_RX
  if(subsume) {
    query <- paste("match(v:RXCUI)-[:SUBSUMES]->(w:RXCUI)<-[:P_RX]-(x:Participant)-[:P_SCT]->(y:ObjectConcept)-[:ISA]->(z:ObjectConcept)",
                   "where z.sctid='", conceptID, "' and v.status='Active' and w.status='Active' and y.active='1' and z.active='1'", sep="")
  } else {
    query <- paste("match(w:RXCUI)<-[:P_RX]-(x:Participant)-[:P_SCT]->(y:ObjectConcept)-[:ISA]->(z:ObjectConcept)",
                   "where z.sctid='", conceptID, "' and w.status='Active' and y.active='1' and z.active='1'", sep="")
  }
  query <- paste(query,
                 " and toLower(w.category)='drug'",
                 " return distinct",
                 " case when(labels(x)=['Participant'])then 'UCDDist'",
                 "      when(labels(x)=['Participant','UCD_Proximal'])then 'UCDProx'",
                 " end as UCDProxDist,",
                 " x.ParticipantId as participantID, x.Sex as Sex, x.UCDDx as UCDDx,",
                 " case when(toInteger(x.OnsetAgeDays)<11)then '0-11'",
                 "      when(toInteger(x.OnsetAgeDays)<101)then '11-100'",
                 "      when(toInteger(x.OnsetAgeDays)<1001)then '101-1000'",
                 "      when(toInteger(x.OnsetAgeDays)<10001)then '1001-10000'",
                 "      when(toInteger(x.OnsetAgeDays) is not null)then '>10000'",
                 "      else null",
                 " end as onsetAgeDays, y.sctid as conceptID, y.FSN as FSN, ",
                 ifelse(subsume, "v.name as Prescription,", "w.name as Prescription,"),
                 " 1 as n", sep="")

  pPrescrip <- cypher(dbcon, query)

  # Relabel null values
  pPrescrip[which(is.na(pPrescrip[,"Sex"])),"Sex"] <- "na"
  pPrescrip[which(is.na(pPrescrip[,"UCDDx"])),"UCDDx"] <- "na"
  pPrescrip[which(is.na(pPrescrip[,"onsetAgeDays"])),"onsetAgeDays"] <- "na"

  # Assemble and return graph with specified nodeVar and prescription nodes and edges
  return(assembleNetComponents(pConcept=pPrescrip,
                               nodeVar1=nodeVar1,
                               nodeVar2="Prescription",
                               vColor1=vColor1,
                               vColor2=vColor2,
                               nedgemin=nedgemin,
                               eopacity=eopacity,
                               vmassf=vMassFactor,
                               vsizefactor=vSizeFactor,
                               vfontsz=c(vFontSize, 0.7*vFontSize),
                               # Adjust font color light for dark vertex color, dark for light
                               vfontcolor=c(ifelse(vColor1<"#CCCCCC", vColor1, "#404040"),
                                            ifelse(vColor2<"#CCCCCC", vColor2, "#404040")),
                               elabVar=elabVar,
                               accMethod=accMethod))

}

##########################################################################################################
# Query role group and (participant or concept) UCD observations using requested parameter values
# Return list of data frames containing vertex and edge configurations
##########################################################################################################

queryAndConstructGraphRoleGroup <- function(nodeVar1, conceptID, vColor1, vColor2, nedgemin, eopacity,
                                            vMassFactor, vSizeFactor, vFontSize, elabVar, accMethod) {

  query <- paste(" match(x:Participant)-[:P_SCT]->(y:ObjectConcept)-[r:ISA*]->(z:ObjectConcept)",
                 " where z.sctid='", conceptID, "' and y.active='1' and z.active='1'",
                 " with x, y, r",
                 " match(y)-[role1:HAS_ROLE_GROUP]->(rg)-[role2:FINDING_SITE]->(rgc:ObjectConcept)",
                 " where role2.active='1' and rgc.active='1'",
                 " with",
                 " case when(labels(x)=['Participant'])then 'UCDDist'",
                 "      when(labels(x)=['Participant','UCD_Proximal'])then 'UCDProx'",
                 " end as UCDProxDist,",
                 " x.ParticipantId as participantID, x.Sex as Sex, x.UCDDx as UCDDx,",
                 " case when(toInteger(x.OnsetAgeDays)<11)then '0-11'",
                 "      when(toInteger(x.OnsetAgeDays)<101)then '11-100'",
                 "      when(toInteger(x.OnsetAgeDays)<1001)then '101-1000'",
                 "      when(toInteger(x.OnsetAgeDays)<10001)then '1001-10000'",
                 "      when(toInteger(x.OnsetAgeDays) is not null)then '>10000'",
                 "      else null",
                 " end as onsetAgeDays,",
                 " startNode(last(r)) as concept,",
                 " type(role2) as role, rgc",
                 " return  UCDProxDist, participantID, Sex, UCDDx, onsetAgeDays,",
                 "         concept.sctid as conceptID, labels(concept) as conceptLabel,",
                 "         concept.FSN as FSN, role, rgc.sctid as roleGroupID, rgc.FSN as roleGroupFSN,",
                 "         count(1) as n", sep="")

  pRoleGroup <- cypher(dbcon, query)

  # Relabel null values
  pRoleGroup[which(is.na(pRoleGroup[,"Sex"])),"Sex"] <- "na"
  pRoleGroup[which(is.na(pRoleGroup[,"UCDDx"])),"UCDDx"] <- "na"
  pRoleGroup[which(is.na(pRoleGroup[,"onsetAgeDays"])),"onsetAgeDays"] <- "na"

  # Assemble and return graph with specified nodeVar and role group nodes and edges
  return(assembleNetComponents(pConcept=pRoleGroup,
                               nodeVar1=nodeVar1,
                               nodeVar2="roleGroupFSN",
                               vColor1=vColor1,
                               vColor2=vColor2,
                               nedgemin=nedgemin,
                               eopacity=eopacity,
                               vmassf=vMassFactor,
                               vsizefactor=vSizeFactor,
                               vfontsz=c(vFontSize, 0.7*vFontSize),
                               # Adjust font color light for dark vertex color, dark for light
                               vfontcolor=c(ifelse(vColor1<"#CCCCCC", vColor1, "#404040"),
                                            ifelse(vColor2<"#CCCCCC", vColor2, "#404040")),
                               elabVar=elabVar,
                               accMethod=accMethod))

}

##########################################################################################################
# Query UCD observations corresponding to participant variables, SNOMED concepts, prescriptions, and
# role groups as specified in function parameter values
# Return list of data frames containing vertex and edge configurations
##########################################################################################################

queryAndConstructGraph <- function(nodeVar1, conceptID, prescripConnector, prescripSubsume,
                                   roleGroupConnector, vColor1, vColor2, vColor3, vColor4,
                                   nedgemin, eopacity, vMassFactor, vSizeFactor, vFontSize) {

  # Construct initial graph components, for participants and concepts
  # First set of vertices from specified participant variable, second set is always fully specified name of concepts
  # Use current node in concept stack
  # Vertex colors assigned from static values (assigned way at the top of this script)
  # Edge min freq filter, edge opacity, vertex mass factor, vertex size factor, and font size taken from on-screen values 
  netComponents <- queryAndConstructGraphPC(nodeVar1=nodeVar1, nodeVar2="FSN", conceptID=conceptID,
                                            vColor1=vColor1, vColor2=vColor2, nedgemin=nedgemin, eopacity=eopacity,
                                            vMassFactor=vMassFactor, vSizeFactor=vSizeFactor, vFontSize=vFontSize,
                                            elabVar=NA, accMethod="PID")

  # Append prescription nodes, if requested
  # First set of vertices from specified participant variable or concept, second set prescriptions
  if(prescripConnector!="none") 
    netComponents <- appendNetwork(netComponents,
                                   queryAndConstructGraphPrescrip(nodeVar1=ifelse(prescripConnector=="nodeVar", nodeVar1, "FSN"),
                                                                  conceptID=conceptID,
                                                                  subsume=prescripSubsume,
                                                                  vColor1=ifelse(prescripConnector=="nodeVar", vColor1, vColor2),
                                                                  vColor2=vColor3,
                                                                  nedgemin=nedgemin, eopacity=eopacity, vMassFactor=vMassFactor,
                                                                  vSizeFactor=vSizeFactor, vFontSize=vFontSize, elabVar=NA,
                                                                  accMethod="PID"))

  # Append role group nodes, if requested
  # First set of vertices from specified participant variable or concept, second set role groups
  # Include role descriptors in edge labels
  if(roleGroupConnector!="none") 
    netComponents <- appendNetwork(netComponents,
                                   queryAndConstructGraphRoleGroup(nodeVar1=ifelse(roleGroupConnector=="nodeVar", nodeVar1, "FSN"),
                                                                   conceptID=conceptID,
                                                                   vColor1=ifelse(roleGroupConnector=="nodeVar", vColor1, vColor2),
                                                                   vColor2=vColor4,
                                                                   nedgemin=nedgemin, eopacity=eopacity, vMassFactor=vMassFactor,
                                                                   vSizeFactor=vSizeFactor, vFontSize=vFontSize, elabVar="role",
                                                                   accMethod="PID"))

  # Return two element list containing vertices and edges
  return(netComponents)

}

##########################################################################################################
# Query SNOMED concepts with an ISA relationship to a node with specific sct ID
##########################################################################################################

queryISAConcept <- function(sctid, filterOpt=NA) {

  # Retrieve all nodes leading to the specified node by ISA relationships
  query <- paste(" match(x:ObjectConcept)-[:ISA]->(y:ObjectConcept)",
                 " where y.sctid='", sctid, "' and x.active='1' and y.active='1'",
                 " return labels(x) as label, x.sctid as sctid, x.FSN as FSN",
                 " order by x.FSN", sep="")
  conceptList <- cypher(dbcon, query)

  # Filter concepts, if requested
  # This, global, approach should be refined based on some sort of user-defined filtering
  if(!is.na(filterOpt)) {
    return(conceptList[which(conceptList[,"FSN"] %in%
                             c("Clinical finding (finding)",
                               "Disease (disorder)",
                               "Mental disorder (disorder)",
                               "Neurological finding (finding)",
                               "Metabolic disease (disorder)",
                               "Motor nervous system finding (finding)",
                               "Disorder of nervous system (disorder)")),])
  } else {
    return(conceptList)
  }

}

##########################################################################################################
# Shiny server function
##########################################################################################################

shinyServer(
  function(input, output, session) {

    ##########################################################################################################
    # Configure global objects
    ##########################################################################################################

    # conceptStack contains the stack of concepts chosen by user
    # csPtr points to the position in the stack corresponding to the current select concept
    conceptStack <- data.frame(nodeLabel=character(), sctid=character(), FSN=character())
    csPtr <- 0

    # pConcept contains participant and conept data from which a network os composed (node and edge data)
    pConcept <- data.frame()

    ##########################################################################################################
    # Concept selection event (add selection to concept stack)
    ##########################################################################################################

    observeEvent(input$conceptSel,{

      # Identify position of selected concept in current concept list
      k <- which(conceptList[,"FSN"]==input$conceptSel)
      if(length(k)>0) {
        # Advance concept stack position and save selected concept
        csPtr <<- csPtr+1
        conceptStack[csPtr,] <<- conceptList[k,]
        rownames(conceptStack) <- NULL
        output$currentRoot <- renderText(HTML(paste("<font color=blue>", conceptStack[csPtr,"FSN"], "</font>", sep="")))
        # Retrieve all nodes leading to the current node (in current stack pos) by ISA relationships
        # Filter list if within three levels of root SNOMED node
        conceptList <<- queryISAConcept(conceptStack[csPtr,"sctid"], filterOpt=ifelse(csPtr<4, "1", NA))
        # Update selection list with current value of NA to avoid triggering an immediate update event
        updateSelectInput(session, "conceptSel", choices=conceptList[,"FSN"], selected=NA)
      }
    
    }, ignoreInit=T)

    ##########################################################################################################
    # Return to parent concept action (return to previous concept in stack)
    ##########################################################################################################

    observeEvent(input$retParentConcept,{

      if(csPtr>1) {
        csPtr <<- csPtr-1
        output$currentRoot <- renderText(HTML(paste("<font color=blue>", conceptStack[csPtr,"FSN"], "</font>", sep="")))
        # Retrieve all nodes leading to the current node (in current stack pos) by ISA relationships
        # Filter list if within three levels of root SNOMED node
        conceptList <<- queryISAConcept(conceptStack[csPtr,"sctid"], filterOpt=ifelse(csPtr<4, "1", NA))
        # Update selection list with current value of NA to avoid triggering an immediate update event
        updateSelectInput(session, "conceptSel", choices=conceptList[,"FSN"], selected=NA)
      }

    }, ignoreInit=T)

    ##########################################################################################################
    # Render network action
    ##########################################################################################################

    observeEvent(input$renderGraph,{

      # Capture on-screen parameter values to be relayed to graph query and construction functions
      nodeVar <- input$nodeVar
      nedgemin <- input$nedgemin
      eopacity <- input$eopacity
      vmassf <- input$vMassFactor
      vsizefactor <- input$vSizeFactor
      vfontsz <- c(input$vFontSize, 0.8*input$vFontSize)
      nCluster <- input$nCluster
      nearestHighlightDeg <- input$nearestHighlightDeg
      prescripConnector <- input$prescripConnector
      prescripSubsume <- input$prescripSubsume
      roleGroupConnector <- input$roleGroupConnector

      # Construct graph
      netComponents <<- queryAndConstructGraph(nodeVar1=nodeVar, conceptID=conceptStack[csPtr,"sctid"],
                                               prescripConnector=prescripConnector, prescripSubsume=prescripSubsume,
                                               roleGroupConnector=roleGroupConnector, vColor1=vc1, vColor2=vc2,
                                               vColor3=vc3, vColor4=vc4, nedgemin=nedgemin, eopacity=eopacity,
                                               vMassFactor=vmassf, vSizeFactor=vsizefactor, vFontSize=vfontsz)

      # Render graph
      if(nrow(netComponents[["vertex"]])>0) {
        # Net regen is always done with physics enabled, but we want it to be disablead after regen
        # Direct disabling of physics (using visPhysics(enabled=F)) has no effect when called immediately after
        # renderVisNetwork(), but is effective when executed frimm within a shiny reactive function
        # So, although not ideal, force disable of physics by toggling the reaction control with physics par val
        updateRadioButtons(session, "physics", selected=T)
        output$g1 <- renderVisNetwork(composeNetwork(vertex=netComponents[["vertex"]], edge=netComponents[["edge"]],
                                                     nodeVar1=nodeVar, nodeVar2="FSN",
                                                     nodeVar3=ifelse(prescripConnector!="none", "Prescription", NA),
                                                     nodeVar4=ifelse(roleGroupConnector!="none", "roleGroupFSN", NA),
                                                     vColor1=vc1, vColor2=vc2, vColor3=vc3, vColor4=vc4,
                                                     nCluster=nCluster, nearestHighlightDeg=nearestHighlightDeg))
        # Compose and render centrality table
        #output$gTable <- DT::renderDataTable(composeGraphTable())
        #updateTextInput(session=session, inputId="reactiveInst", value="physicsOff")
        updateRadioButtons(session=session, inputId="physics", selected=F)
      } else {
        output$g1 <- NULL
        #output$gTable <- NULL
      }

    }, ignoreInit=T)      

    ##########################################################################################################
    # Stabilized event
    # Disable physics after stabilization during initial network construction
    # This prevents dynamic repositioning of vertices as connected vertices are moved
    # Note that edges are not redrawn during dynamic movement, but are with the stabilize() function
    ##########################################################################################################

    observeEvent(input$stabilized, {
      print("stabilized")
      visPhysics(visNetworkProxy("g1"), enabled=F)
    })
    
    ##########################################################################################################
    # Physics event
    # Enable or disable physics operations (enabling causes repositioning of nodes, if not fixed, and edges)
    # Do not disable on first evaluation, during program initialization
    ##########################################################################################################

    observeEvent(input$physics, {
      print("physics")
      if(input$physics) {
        visPhysics(visNetworkProxy("g1"), enabled=T, timestep=0.25, minVelocity=10, maxVelocity=50,
                   solver=c("barnesHut", "repulsion")[1],
                   barnesHut=list("avoidOverlap"=0.5, "springLength"=100, "springConstant"=0.5, "damping"=0.5),
                   #repulsion=list("nodeDistance"=1000),
                   stabilization=list("enabled"=T, "iterations"=1000))
      } else {
        visPhysics(visNetworkProxy("g1"), enabled=F)
      }
    }, ignoreInit=T)

    ##########################################################################################################
    # Redraw edge event
    # Redraw by fixing vertex positions, stabilizing, then freeing vertex psitions
    ##########################################################################################################

    #observeEvent(input$redrawEdge, {
    #  print("redrawEdge")
    #  # Fix positions
    #  visUpdateNodes(visNetworkProxy("g1"), data.frame("id"=vertex[,"id"], "fixed"=T))
    #  # Stabilize
    #  visStabilize(visNetworkProxy("g1"))
    #  # Free positions
    #  updateTextInput(session=session, inputId="reactiveInst", value="vertexFixedOff")
    #}, ignoreInit=T)

    ##########################################################################################################
    # Vertex shift-click event
    # Triggered by java script contained in the click element of the visEvents parameter of the graph
    # rendered by composeNetwork()
    # Verify that a vertex has been clicked (input$shiftClick[["nodes"]] length one or greater)
    # Hide all vertices not connected to selected vertex and all edges attached to hidden vertices
    ##########################################################################################################

    observeEvent(input$shiftClick, {
      print("shiftClick")
      # Identify selected vertex
      v <- input$shiftClick[["nodes"]]
      if(length(v)>0) {
        v0 <- v[[1]][1]
        print(v0)
        vertex <- netComponents[["vertex"]]
        edge <- netComponents[["edge"]]
        # Identify all edges connected to selected vertex
        ke <- which(edge[,"from"]==v0 | edge[,"to"]==v0)
        # Identify all vertices connected to selected vertex
        kv <- which(vertex[,"id"] %in% unlist(edge[ke,c("from", "to")]))
        # Hide vertices that are not connected to selected vertex
        vertex[,"hidden"] <- T
        vertex[kv,"hidden"] <- F
        vertex[,"physics"] <- F
        vertex[kv,"physics"] <- T
        output$g1 <- renderVisNetwork(composeNetwork(vertex=vertex, edge=edge[ke,],
                                                     nodeVar1=input$nodeVar, nodeVar2="FSN",
                                                     nodeVar3=ifelse(input$prescripConnector!="none", "Prescription", NA),
                                                     nodeVar4=ifelse(input$roleGroupConnector!="none", "roleGroupFSN", NA),
                                                     vColor1=vc1, vColor2=vc2, vColor3=vc3, vColor4=vc4,
                                                     nCluster=input$nCluster, nearestHighlightDeg=input$nearestHighlightDeg))
        #updateTextInput(session=session, inputId="reactiveInst", value="physicsOff")
        #updateRadioButtons(session=session, inputId="physics", selected=F)
      }
    }, ignoreInit=T)

    ##########################################################################################################
    # Vertex alt-click event
    # Triggered by java script contained in the click element of the visEvents parameter of the graph
    # rendered by composeNetwork()
    # Verify that a vertex has been clicked (input$alt[["nodes"]] length one or greater)
    # Save existing graph construct then generate new graph from selected node and those with a relationship
    ##########################################################################################################

    observeEvent(input$altClick, {
      print("altClick")
      # Identify selected vertex
      v <- input$altClick[["nodes"]]
      if(length(v)>0) {
        v0 <- v[[1]][1]
        print(v0)
        print(netComponents[["vertex"]])
        vertex <- netComponents[["vertex"]]
        edge <- netComponents[["edge"]]
        # Identify all edges connected to selected vertex
        ke <- which(edge[,"from"]==v0 | edge[,"to"]==v0)
        # Identify all vertices connected to selected vertex
        kv <- which(vertex[,"id"] %in% unlist(edge[ke,c("from", "to")]))
        # Hide vertices that are not connected to selected vertex
        vertex[,"hidden"] <- T
        vertex[kv,"hidden"] <- F
        vertex[,"physics"] <- F
        vertex[kv,"physics"] <- T
        output$g1 <- renderVisNetwork(composeNetwork(vertex=vertex, edge=edge[ke,],
                                                     nodeVar1=input$nodeVar, nodeVar2="FSN",
                                                     nodeVar3=ifelse(input$prescripConnector!="none", "Prescription", NA),
                                                     nodeVar4=ifelse(input$roleGroupConnector!="none", "roleGroupFSN", NA),
                                                     vColor1=vc1, vColor2=vc2, vColor3=vc3, vColor4=vc4,
                                                     nCluster=input$nCluster, nearestHighlightDeg=input$nearestHighlightDeg))
        #updateTextInput(session=session, inputId="reactiveInst", value="physicsOff")
        #updateRadioButtons(session=session, inputId="physics", selected=F)
      }
    }, ignoreInit=T)

    ##########################################################################################################
    # Restore graph after subnetting
    ##########################################################################################################

    observeEvent(input$restoreVertex, {
      print("restoreVertex")
      output$g1 <- renderVisNetwork(composeNetwork(vertex=netComponents[["vertex"]], edge=netComponents[["edge"]],
                                                   nodeVar1=input$nodeVar, nodeVar2="FSN",
                                                   nodeVar3=ifelse(input$prescripConnector!="none", "Prescription", NA),
                                                   nodeVar4=ifelse(input$roleGroupConnector!="none", "roleGroupFSN", NA),
                                                   vColor1=vc1, vColor2=vc2, vColor3=vc3, vColor4=vc4,
                                                   nCluster=input$nCluster, nearestHighlightDeg=input$nearestHighlightDeg))
      #updateTextInput(session=session, inputId="reactiveInst", value="physicsOff")
      #updateRadioButtons(session=session, inputId="physics", selected=F)
    }, ignoreInit=T)

    ##########################################################################################################
    # Execution begins here
    ##########################################################################################################

    # Query SNOMED root node
    csPtr <- 1
    query <- "match(x) where x.FSN contains 'SNOMED CT Concept' and x.active='1' return labels(x) as label, x.sctid as sctid, x.FSN as FSN limit 1"
    conceptStack[csPtr,] <- cypher(dbcon, query)[1,]
    output$currentRoot <- renderText(HTML(paste("<font color=blue>", conceptStack[csPtr,"FSN"], "</font>", sep="")))

    # Retrieve all nodes leading to the root node by ISA relationships
    # Filter list to nodes of interest
    conceptList <- queryISAConcept(conceptStack[csPtr,"sctid"], filterOpt="1")

    # Update selection list with current value of NA to avoid triggering an immediate update event
    updateSelectInput(session, "conceptSel", choices=conceptList[,"FSN"], selected=NA)

  }
)