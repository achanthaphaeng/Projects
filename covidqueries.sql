--testing inported tables

select * from CovidDeaths
order by 3,4

select * from CovidVaccine
order by 3,4

--select data that we are going to be using

select location, date, total_cases, new_cases, total_deaths, population 
from CovidDeaths
order by 1,2

--looking at total cases vs total deaths
--likelihood of dying if you contract COVID in US

select location, date, total_cases, total_deaths, (total_deaths/total_cases)*100 as 'percentage'  
from CovidDeaths
where location like '%United States%'
order by 1,2

--looking at total cases vs population
--shows percentage of population got COVID

select location, date, population, total_cases, (total_cases/population)*100 as 'percentage' 
from CovidDeaths
where location like '%United States%'
order by 1,2

--countries with the highest infection rate compared to population
--my answer
select location, population, total_cases, (total_cases/population)*100 as 'percentage' 
from CovidDeaths
where date = dateadd(day, -1, cast(getdate() as date))
order by percentage desc
 
 --key
 select location, population, max(total_cases) as 'total_cases', max((total_cases)/population)*100 as 'percentage'
 from CovidDeaths
 group by location, population
 order by percentage desc

 --countries with highest death rate
select location, population, total_deaths, (total_deaths/population)*100 as 'percentage' 
from CovidDeaths
where date = dateadd(day, -1, cast(getdate() as date))
order by percentage desc

--continents w/ highest death count
select continent, max(cast(total_deaths as int)) as TotalDeath
from CovidDeaths
where continent is not null
group by continent
order by TotalDeath desc

--global numbers
select sum(new_cases) as totalcases, sum(cast(new_deaths as int)) as totaldeaths-- total_deaths, (total_deaths/total_cases)*100 as DeathPercentage
from CovidDeaths
where continent is not null
--group by date
--order by date

--looking at total population vs vaccinations w/ rolling sum per location
select dea.continent, dea.location, dea.date, dea.population, vac.new_vaccinations, 
sum(cast(vac.new_vaccinations as int)) over (partition by dea.location order by dea.location, dea.date) as rollingpeoplevac
from CovidDeaths dea
join CovidVaccine vac
on dea.location = vac.location
and dea.date = vac.date
where dea.continent is not null
order by 2,3

--Use CTE
with PopVsVac (Continent, location, date, population, new_vaccinations, rollingpeoplevac)
as (
select dea.continent, dea.location, dea.date, dea.population, vac.new_vaccinations, 
sum(cast(vac.new_vaccinations as int)) over (partition by dea.location order by dea.location, dea.date) as 'rolling sum per location by date'
from CovidDeaths dea
join CovidVaccine vac
on dea.location = vac.location
and dea.date = vac.date
where dea.continent is not null
--order by 2,3
)
select * , (rollingpeoplevac/population)*100  
from PopVsVac

--temp table
create table #percentpopulationVaccinated
(
Continent nvarchar(255),
Location nvarchar(255),
date datetime,
population numeric,
new_vaccinations numeric,
rollingpeoplevaccinated numeric,
)
insert into #percentpopulationVaccinated

select dea.continent, dea.location, dea.date, dea.population, vac.new_vaccinations, 
sum(cast(vac.new_vaccinations as int)) over (partition by dea.location order by dea.location, dea.date) as 'rolling sum per location by date'
from CovidDeaths dea
join CovidVaccine vac
on dea.location = vac.location
and dea.date = vac.date
where dea.continent is not null
order by 2,3

select * from #percentpopulationVaccinated

--create view to store data 
create view percentpopulationVaccinated 
as
select dea.continent, dea.location, dea.date, dea.population, vac.new_vaccinations, 
sum(cast(vac.new_vaccinations as int)) over (partition by dea.location order by dea.location, dea.date) as 'rolling sum per location by date'
from CovidDeaths dea
join CovidVaccine vac
on dea.location = vac.location
and dea.date = vac.date
where dea.continent is not null
--order by 2,3