# Based off the latest code written by Bryan, with a network closer to demographics

using BenchmarkTools
using LightGraphs
using SimpleWeightedGraphs
using MetaGraphs
using Distributions
using CSV
categ = Distributions.Categorical
import StatsBase: sample, sample!
using DataFrames
DF = DataFrames

include("FastSIR_graphs.jl")

FWG = FastSIRWithWeightedNodes
F  = FastSIRCommon

# Use a const immutable named tuple for efficiency
# I can change values within this constant, but I cannot add another member
# When developing the code, use non-consts in the global space
p = (
    epidemic_sims = 10,  # ???
    households = 10,     # number of households
    household_size = 4,
    #class_size = 20,
    schoolgroup_size = 20,  # all-to-all contacts
    workgroup_size = 10,
    employment_rate = 0.9,
    recovery_rate = 1,
    global_infection_rate = 1,
    house_infectivity = .1,
    work_infectivity = .05,
    τ = 1.,  # transmission factor
    γ = 1.,  # recovery rate
    initial_infected_perc = 0.05,
    initial_infected = 1,  # initial number of people infected
)

function loadPickledPop(filename)
    populace_df = CSV.read(filename, delim=',')
    return populace_df  # ???
end

#p.population = p.household_size * p.households
people = p.household_size * p.households
population = people

# symbols take 8 bytes
work_classes = [:default, :unemployed, :school,]
duties = [:None, :school, :work,]

# --------------------------------
# No worries about efficiency at this stage
# --------------------------------
using Random
mutable struct Person
    attributes::Dict
end

# a function which returns a list of tuples randomly assigning nodes
# to groups of size n
function  nGroupAssign(members::Array{Int,1}, group_size::Int)
    lg = length(members)
    shuffle!(members)
    pos = 1
    group_number = 1
    dict = Dict()
    while true
        if (pos+group_size) > lg
            dict[group_number] = @view members[pos:end]
            #dict[groupNumber] = (itertools.islice(members, pos, pos + groupSize))
            break
        else
            dict[group_number] = @view members[pos : pos+group_size-1]
        end
        group_number += 1
        pos += group_size
    end
    return dict
end

members = collect(1:100)
group_size = 23
dict = nGroupAssign(members, group_size::Int)

# IMPORTANT
# If I shuffle the dictionaries,

# a function which returns a list of tuples randomly assigning
# nodes to groups: p_n=(p1,p2,...,pn), sum(p_n)==1. is true, and
function p_nGroupAssign(member_indices, p_n)
   lg = length(member_indices)
    shuffle(member_indices)
    pos = 1
    group_number = 1
    dict = Dict()
    println("p_n = $p_n, sum(p_n) = $(sum(p_n))")
    while true
        group_size = rand(categ(p_n))
        #group_size = Random.choices(range(length(p_n)), weights=p_n)[0]+1
        println("group_size: $group_size")
        if (pos+group_size) > lg
            dict[group_number] = @view member_indices[pos:end]
            break
        end
        dict[group_number] = @view member_indices[pos : pos+group_size-1]
        group_number += 1
        pos += group_size
    end
    return dict
end

member_indices = members
p_n = [.2,.3,.5]
dict1 = p_nGroupAssign(member_indices, p_n)

#def p_attributeAssign(memberIndices, attributes, probabilities):
function p_attributeAssign(member_indices, attributes, probabilities)
    shuffle!(member_indices)  # Where should the shuffling occur?
    probabilities ./= sum(probabilities)
    if length(attributes) != length(probabilities)
        println("Error: probabilibies and attributes must have same length")
        drop() #ERROR
    end
    dict = Dict()
    for attribute in attributes
        dict[attribute] = []
    end
    #dict = {attribute: [] for attribute in attributes}

    for index in member_indices
        #assignment = random.choices(attributes, weights = probabilities)[0]
        # QUESTION: why zero index selection?
        assignment = attributes[rand(categ(probabilities))]
        push!(dict[assignment], index)
    end
    return dict
end

# Assume that attributes are arrays of integers
member_indices = members
attributes = collect(3:5)
probabilities = [.3, .2, .5]
dict2 = p_attributeAssign(member_indices, attributes, probabilities); listDict(dict2)

function listDict(dict)
    for k in keys(dict)
        #println("items: $(length(dict[k])), dict[$k]: $(dict[k])")
        println("items: $(length(dict[k]))") #, dict[$k]: $(dict[k])")
    end
end

filename = "Leon_Formatted/people_formatted.csv"
populace_df = loadPickledPop(filename)
rename!(populace_df, :Column1 => :person_id)

# replace 'X' by -1 so that columns are of the same type
replace!(populace_df, "X" ==> -1)


# for loading people objects from file
function genPop(people, attributeClasses, attributeClass_p)
    #population = {i: {} for i in range(people)}
    population = Dict()

    for i in people
        population[i] = Dict()
    end

    for attributeClass in attributeClasses
        assignments = p_attributeAssign(collect(people),
                attribute_classes[attribute_class],
                attribute_class_p[attribute_class])
        for  key in assignments
            for i in keys(assignments)
                population[i][attributeClass] = key
            end
        end
    end

    return population
end

# NOT YET TESTED
#genPop(people, attribClasses, attribute_class_p)

#takes a dict of dicts to represent populace and returns a # list
# of dicts of lists to represent groups of people with the
# same attributes
function sortPopulace(populace_df, categories)
    groups = Dict()
    for c in categories
        groups[c] = []
    end
    for (i,c) in enumerate(categories)
        grps = groupby(df, c)
        #grps = by(df, c)
        for g in grps
            push!(groups[c], g)
        end
    end

    return groups
end

categories = [:sp_hh_id, :work_id, :school_id]
# Categories is a list of categories
#column1 in each group is the person_id. I should rename the colums of the DataFrame
# column name person_id became person
groups = sortPopulace(populace_df, categories)

# Create a set of methods to generate graphs

# 1) create a dense graph, given a group
function createDenseGraph(df, group)
    n = length(group)
    # add Metadata to the nodes and edges with the person_id, or a unique id in 1:population_size
    graph = SimpleGraph(n, div(n*(n-1),2))
end

graph = createDenseGraph(df, 1:10)

# 2) create a graph with each node having a fixed degree, where the nodes
#    are chosen randomly
function createErdosRenyiGraph(group, m::Int) #p::Float64)
    # produce graph with an average degree set to m
    # Given a group of size n, there are a maximum of n*(n-1)/2 edges per node
    # so on average, (n-1)/2 neighbors per node.
    # If the goal is to have m neighbors per node, nodes must be assigned
    # with probability 2*m/(n-1)
    n = length(group)
    p = 2*m / (n-1)
    # Add node and edge metadata (person_id or index, and infection rate)
    graph = erdos_renyi(n, p)
end

graph = createErdosRenyiGraph(1:1000, 4)

# Given a group (i.e., workplace, school, home), break it up into smaller groups
# of size n
#function breakupGroup(group::Vector{any}, nb_sub_groups::Int)
# Vector{any} does not work
function breakupGroup(group; subgroup_size::Int64=20)
# return a smaller number of groups
# Group is a list. Groups are assigned according to uniform distribution with prob 1/nb_sub_groups
   nb_subgroups = div(length(group), subgroup_size) + 1
   #println("$nb_subgroups, subgroup_size: $subgroup_size, group_size: $(length(group))")
   rands = rand(1:nb_subgroups, length(group))
   # break this into groups
   groups = Dict{Int64, Vector{Int64}}()
   for i in 1:nb_subgroups
       groups[i] = []
   end
   for (i,id) in enumerate(rands)
       push!(groups[id], i)
   end
   # return a dictionary of Vector{Int}
   groups  # necessary or else nothing is returned
end

s = breakupGroup(rand(1:2000, 300), subgroup_size=50)
print("length(s)= $(length(s))")
for i in s
    println(length(i))
end

function breakupSchool(group; class_size::Int=20)
    breakupGroup(group, subgroup_size=class_size)
end

function breakupWorkplace(group; workplace_size::Int=30)
    breakupGroup(group, subgroup_size=workplace_size)
end

a = 3

# Create one graph per group. Let us start with schools
schools = groups[:school_id]
# Remove schools with a school_id of 'X'

function createSchoolGraphs(schools)
    school_graphs = []
    for (i,grp) in enumerate(schools)
        groups_ = breakupSchool(grp.person; class_size=20)
        for k in keys(groups_)  # g is a dictionary
            g = groups_[k]
            push!(school_graphs, createErdosRenyiGraph(g, 20))
        end
    end
    return school_graphs
end

# Takes about 4 sec for synthetic population
# schools[1]: all the people not in school, so the school_id is 'X'
schools_ = schools[2:end]
@time G = createSchoolGraphs(schools_)

a = 3
school_graphs = G

for G in school_graphs
    print("[$(nv(G)), $(ne(G))], ")
end

# Even though there are many more graphs, the search new infections should
# be much faster, because many nodes will have far fewer neighbors to search.
sum(nv.(school_graphs))
sum(ne.(school_graphs))

#----------------------------------------------
function createWorkplaceGraphs(workplaces; group_size=20)
    work_graphs = []
    for (i,grp) in enumerate(workplaces)
        #println(grp.person)
        #println(length(grp.person))
        # Remove lines with 'X' in :work_id
        #grp[grp.work_id == 'X']
        groups_ = breakupWorkplace(grp.person; workplace_size=group_size)
        for k in keys(groups_)  # g is a dictionary
            g = groups_[k]
            G = createErdosRenyiGraph(g, 20)
            if nv(G) > 1
                push!(work_graphs, G)
            end
        end
    end
    return work_graphs
end

for (i,grp) in enumerate(workplaces_)
    g = grp.work_id .== 'X'
    if grp.work_id[1] == 'X'  # why aren't any with an 'X'? I DO NOT FOLLOW
        #println("$i, $(grp.work_id[1])")
    end
    println("$i, $(grp.work_id[1])")
end

# Vector{SubDataFrame{DataFrame,DataFrames.Index,Array{Int64,1}}}
workplaces_ = groups[:work_id]


# perhaps small world Strogatz graph is better (as per Bryan Azbill)
@time wp_graphs = createWorkplaceGraphs(workplaces_, group_size=20)

for G in wp_graphs
    print("[$(nv(G)), $(ne(G))], ")
end
sum(nv.(wp_graphs))
sum(ne.(wp_graphs))

a = 3


work_ = schools[2:end]
createWorkplaceGraphs()

a = 3

#connect list of groups with weight
#TODO update to use a weight calculating function
function clusterDenseGroups
    # keys are attributes, :school_id, etc
    # each group has a number of subgroups
    # Create an all_to_all graph for each subgroup
    # Ideally, each group type would be a separate graph in a multiplex structure
    #println("grps= ", groups)
    println("keys(groups)= ", keys(groups))
    for key in keys(groups)
        println("key= ", key)
        println("   size: ", length(groups[key]))
    end
    key = :school_id
    sz_group = length(groups[key])
    grp = groups[key]
    print("nb schools: ", length(groups[key]))
    for i in 1:sz_group
        # for now, ignore groups > 10
        sz = nrow(grp[i])
        # divide each group into classes
        # connect all to all in  classes (size 20, or perhaps randomized, with changing day to day)
        # or treat class as a population for faster computation, then assign infectiousness to
        # a random student in the class.
        if sz < 100
            println("nbrows subgroup $i: ", sz)
            continue
        end
    end
    return
end

#=
        #println("grp_type= $grp_type")
        grps = groups[key]
        println("lgth: ", length(grps))
        for grp in 1:length(grps)
            count = length(grp)
            #println("length(grp), length(grps)= ", count, length(grps))
            break
            continue
            grp_sz = length(grp)
            scaled_weight = 1. / sqrt(grp_sz) # why?
            println("id: grp_siz= ", groups[:school_id])
            println("grp_siz= ", grp_sz)
            for i in 1:grp_sz
                for j in i+1:grp_sz
                    # graph is undirected
                    add_edge!(graph, i, j, scaled_weight)
                end
            end
        end
    end
end
=#
sz_populace = size(populace_df,1)
graph = SimpleWeightedGraph(sz_populace)

edge_weight = 1.2 # set this correctly later
clusterDenseGroups(graph, groups, edge_weight)

a = 3
"""
#connect list of groups with weight
#TODO update to use a weight calculating function
function clusterDenseGroups(graph, groups, weight)
    for key in keys(groups)
        if key != :none
            member_count = length(groups[key])
            member_weight_scalar = sqrt(member_count)
            for i in 1:member_count
                for j in 1:i
                    graph.add_edge(groups[key][i],groups[key][j], transmission_weight = weight/memberWeightScalar)
                end
            end
        end
    end
end


function clusterByDegree_p(graph, groups, weight,degree_p)
    #some random edges may be duplicates, best for large groups
    connectorList = []

    for key in keys(groups)
        if key != :none
            member_count = length(groups[key])
            connector_list = []
            for i in 1:member_count
                node_degree = rand(categ(degree_p, length(degree_p)), length(degree_p))
                #node_degree = random.choices(range(len(degree_p)), weights = degree_p)
                connector_list = vcat(connector_list, repeat([i], node_degree[0]))
                #connector_list.extend([i] * node_degree[0])
            end
            shuffle(connector_list)

            i = 0
            while i < length(connector_list)
                ## ??
                graph.add_edge(connectorList[i],connectorList[i+1],transmission_weight = weight)
                i = i+2
            end
        end
    end
end


function clusterWith_gnp_random(graph, groups, weight, avg_degree)
    for key in keys(groups)
        if key != :none
            member_count = length(groups[key])
            # ???
            edge_prob = (member_count*avg_degree) / (member_count*(member_count-1))
            # ???
            graph2 = nx.fast_gnp_random_graph(memberCount,edgeProb)
            # ??? Check call
            graph.add_edges_from(graph2.edges())
        end
    end
end


#clusters groups into strogatz small-worlds networks

#clusters groups into strogatz small-worlds networks
function strogatzDemCatz(graph, groups, weight, local_k, rewire_p)
    if local_k % 2 != 0
        print("Error: local_k must be even")
    end

    for key in groups
        if key != None
            memberCount = length(groups[key])
            if local_k >= memberCount
                println("warning: not enough members in group for .2f".format(local_k) + "local connections in strogatz net")
                continue
            end

            group = groups[key]
            #unfinished for different implementation to not leave any chance of randomly selecting the same edge twice
            #rewireCount = np.random.binomial(memberCount, rewire_p)
            #rewireList = np.choices(group, rewireCount)*2

            for i in 1:member_count
                if memberCount < 5
                    println("stop")
                end

                for j in range(div(local_k,2))
                    rewire_roll = rand()

                    if rewire_roll < rewire_p
                        # ??
                        graph.add_edge(i, (i + random.choice(range(memberCount - 1))) % memberCount, transmission_weight=weight)
                    else
                        # ??
                        graph.add_edge(i, i + j, transmission_weight=weight)
                    end

                    if rewire_p<rewireRoll<2*rewire_p
                        # ??
                        graph.add_edge(i, (i + random.choice(range(memberCount - 1))) % memberCount,transmission_weight=weight)
                    else
                        # ??
                        graph.add_edge(i, i - j, transmission_weight=weight)
                    end
                end
            end
        end
    end
end
drop


#WIP
function clusterGroupsByPA(graph, groups)
    for key in keys(groups)
        member_Count = length(key)
    end
end
# --------------------------------

age_groups = Int[]  # USED BY PROGRAM?
G = SimpleGraph()

import Random
import Distributions
categ = Distributions.Categorical
## generate population
citizens = 1:population
# House numbers for each citizen shuffled
# HOW TO ASSIGN AGE TO HOUSEHOLDS. Is shuffling required?
house_numbers = Random.shuffle([i%p.households for i in citizens])

age_choices = [
   (1,5),
   (6,18),
   (19,65),
   (66,120)]
age_weights = [0.05, 0.119, 0.731, 0.1]  # from census.gov for tallahassee 2019
categ = Distributions.Categorical
age_indexes = rand(categ(age_weights),population)  # in [1,length(ageChoices)
age_brackets = age_choices[age_indexes]

#workClasses = (:default, :unemployed, :school)
work_classes = (none=1, default=2, unemployed=3, school=4,)  # immutable tuple

function genWorkType(age_index; age_choices, p)
    if age_index == 1 #age_choices[1]
        return work_classes.none
    elseif age_index == 2 #age_choices[2]
        return work_classes.school
    elseif rand() < p.employment_rate
        return work_classes.default
    else
        return work_classes.unemployed
    end
end


# return index into employment tuple
#=
for i in 1:10
    age_indexes = rand(1:4, 100)
    println([sum(age_indexes .== i) for i in 1:4])
    work_types = genWorkType.(age_indexes; age_choices=age_choices, p=p)# , age_choices, p)
    println([sum(work_types .== i) for i in 1:4])
end
println(work_types[:])
=#

# might not work without the semi-colon (might not vectorize with the "." operator)
# returns an index [1:length(work_places]
work_types = genWorkType.(age_indexes; age_choices=age_choices, p=p)
# citizens: 1:population
citizen_work_types = [(work_types[i], citizens[i]) for i in 1:population]
# column vector of pairs

# Mix the students, unemployed, working ...
# Mix the work_types array
Random.shuffle!(work_types)
work_classes = (none=1, default=2, unemployed=3, school=4,)  # immutable tuple

working    = work_types[work_types .== work_classes.default]
students   = work_types[work_types .== work_classes.school]
unemployed = work_types[work_types .== work_classes.unemployed]
none_class = work_types[work_types .== work_classes.none]   # What does this correspond to?
@assert length(working) + length(students) + length(unemployed) + length(none_class) == population

class_count     = Int(ceil(length(students)/ p.class_size))
workgroup_count = Int(ceil(length(working)/ p.workgroup_size))
environment_count  = class_count + workgroup_count  # ???
# classes
# For each students, what class are their in: (student_id, class_id)
# All classes could be different sizes according to some distribution
school_assignments = [[students[i],i%class_count] for i in 1:length(students)]
work_assignments   = [[working[i], i%workgroup_count] for i in 1:length(working)]
# a 0 denotes nothing
unassigned         = [[unemployed[i], 0] for i in 1:length(unemployed)]
none_class         = [[none_class[i], 0] for i in 1:length(none_class)]

school_assignments_ = vcat(school_assignments, work_assignments, unassigned, none_class)
# Why sort?
# What is assignments for?  Graph construction?
# Sort by second index, unzip, and extract the 2nd indeo
sort_sa = sort(school_assignments_)  # sort by 1st arg of 2-tuple
# list of assignments: schools, work, unassigned
assignments = [sort_sa[i][2] for i in 1:length(sort_sa)];
#=

sims = np.array([citizens,houseNumbers,workTypes,assignments])
graph = nx.Graph()
graph.add_nodes_from(list(range(population)))
=#
sims = hcat(citizens, house_numbers, work_types, assignments)


# Distribute workers into different environments

# citizens connected all to all
#function to create homogeneous group
function groupCitizens!(graph, citizens, weight)
    group_size = length(citizens)
    max_neighbors = 10
    neighbors = fill(0, max_neighbors)  # preallocate
    #println("First 5 neighbors: ", neighbors[1:5])
    #println("group_size (nb citizens): ", group_size)

    for i in 1:group_size
        if length(citizens) > max_neighbors
            # for each citizen, generate max_neigh random contacts.
            # neighbors might contains self-neighbors
            sample!(citizens, neighbors; replace=false)
        else
            #print("else, ")
            neighbors = copy(citizens)
        end
        #println("before add_edge: ", neighbors)

        # if an edge is repeated, it is only counted once
        for j in 1:length(neighbors)
            add_edge!(graph, citizens[i], neighbors[j], weight)
        end
    end
end


#link population in the same households
# If household has 6 nodes, there are 6*5/2 = 15 connection
function addHouses!(graph, citizens, house_numbers)
    citizen_houses = hcat(collect(citizens), house_numbers)
    for i in 1:p.households
        cond = citizen_houses[:,2] .== i-1
        house_occupants = citizen_houses[:,1][cond]
        #if length(house_occupants) > 0
            #println("$i, $house_occupants")
        #end
        # Each citizen should only have contact with nb_contacts, chosen randomly.
        # so for each citizen, choose
        groupCitizens!(graph, house_occupants, p.house_infectivity)
    end
end

# Link population in the same work environment
# If work environment is too large, not everybody can be connected to everybody
# If work has 15 employees, connections are 15*16/2 = 120
# If work has 1000 employees, connections are 1000*1001/2 = 500,000 (too much)
# So we assume that somebody has no more than 10 contacts
# link population in the same work environment

function addWorkplaces!(graph, citizens, assignments, params)
    assignment_groups = hcat(collect(citizens), assignments)
    for i in 1:environment_count
        cond = assignment_groups[:,2] .== i-1
        environment_group = assignment_groups[:,1][cond]
        if length(environment_group) > 0
            # Citizens are contiguous. They should be mixed (not clear that would have an effect)
            #println("length(environment_group): $(length(environment_group))")
            #println("environment_group: $(environment_group))")
        end
        groupCitizens!(graph, environment_group, params.work_infectivity)
    end
end

# Graph with one node per citizen. No edges
graph = SimpleWeightedGraph(population)

addHouses!(graph, citizens, house_numbers)
addWorkplaces!(graph, citizens, assignments, p)
# remove self-edges
print("nb edges: ", ne(graph))
for n in 1:nv(graph)
    if has_edge(graph, n,n) == true
        println("has edge: $n, $n")
    end
end
for n in 1:nv(graph)
    rem_edge!(graph, n, n)
end
print("nb edges: ", ne(graph))
println(params)


graph = SimpleGraph(100)
add_edge!(graph, 1,1)
println("ne(graph): ", ne(graph))
println("has_edge(graph, 1, 1): ", has_edge(graph, 1,1))
rem_edge!(graph, 1, 1)
println("ne(graph): ", ne(graph))
println("has_edge(graph, 1, 1): ", has_edge(graph, 1,1))

# A multilayer would allow multiple people from the same household to go to the same workplace.
# A single graph cannot have two edges between two nodes.

params = Dict()
τ = p.house_infectivity
γ = p.work_infectivity
t_max = 5.
p = 0.05
params = (τ=τ, γ=γ, t_max=t_max, p=p)
infected = 1:20 |> collect
#params = (τ=3, γ=1.0, t_max=5., p=0.05)
@time times, S, I, R = FWG.simulate(graph, params, infected)

F.myPlot(times, S, I, R)

"""

"""
plt.show()
plt.ylabel("citizens")
plt.xlabel("time")
    plt.plot(t,S)
    plt.plot(t,I)
    plt.plot(t,R)
    t,S,I,R = EoN.fast_SIR(graph, globalInfectionRate, recoveryRate, rho = 0.01, transmission_weight ='transmission_weight')
for i in range(epidemicSims):
plt.show()
nx.draw(graph)