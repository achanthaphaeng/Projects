--test nashville housing table
select * from NashvilleHousing

--Cleaning Data in SQL Queries
select * from NashvilleHousing

--Standardize Date Format
select SaleDateConverted, Convert(date, SaleDate)
from NashvilleHousing

update nashvilleHousing
set SaleDate = Convert(date,SaleDate)

alter table NashvilleHousing
Add SaleDateConverted Date;
update NashvilleHousing
Set SaleDateConverted = convert(date, SaleDate)

--populate property address data
select * from NashvilleHousing
--where propertyAddress is null
order by ParcelID

select a.ParcelID, a.PropertyAddress, b.ParcelID, b.PropertyAddress, isnull(a.propertyAddress, b.propertyAddress) 
from NashvilleHousing a 
join NashvilleHousing b 
	on a.ParcelID = b.ParcelID
	and a.[UniqueID ] <> b.[UniqueID ]
	where a.PropertyAddress is null

update a
set propertyAddress = isnull(a.propertyAddress, b.propertyAddress)
from NashvilleHousing a 
join NashvilleHousing b 
	on a.ParcelID = b.ParcelID
	and a.[UniqueID ] <> b.[UniqueID ]

--breaking out address into individual columns (address, city, state)
select PropertyAddress from NashvilleHousing
--delimit comma
select
substring(propertyAddress, 1, charindex(',',PropertyAddress) -1) as Address,
substring(propertyAddress, charindex(',',PropertyAddress) +1, len(PropertyAddress)) as Address
from NashvilleHousing

alter table NashvilleHousing
Add PropertySplitAddress Nvarchar(255)

Update NashvilleHousing 
set PropertySplitAddress = substring(propertyAddress, 1, charindex(',',PropertyAddress) -1)

alter table NashvilleHousing
Add PropertySplitCity Nvarchar(255)

Update NashvilleHousing 
set PropertySplitCity = substring(propertyAddress, charindex(',',PropertyAddress) +1, len(PropertyAddress))

select * from NashvilleHousing

select
parsename(replace(ownerAddress, ',', '.'), 3),
parsename(replace(ownerAddress, ',', '.'), 2),
parsename(replace(ownerAddress, ',', '.'), 1)
from NashvilleHousing

alter table NashvilleHousing
Add OwnerSplitAddress Nvarchar(255)

Update NashvilleHousing 
set OwnerSplitAddress = parsename(replace(ownerAddress, ',', '.'), 3)

alter table NashvilleHousing
Add OwnerSplitCity Nvarchar(255)

Update NashvilleHousing 
set OwnerSplitCity = parsename(replace(ownerAddress, ',', '.'), 2)

alter table NashvilleHousing
Add OwnerSplitState Nvarchar(255)

Update NashvilleHousing 
set OwnerSplitState = parsename(replace(ownerAddress, ',', '.'), 1)

select * from NashvilleHousing

--change y and n in "sold as vacant" field

select distinct(soldAsVacant), count(soldasvacant)
from nashvillehousing
group by soldasvacant
order by 2

select soldasvacant, case when soldasvacant = 'Y' then 'Yes'
						  when soldasvacant = 'N' then 'No'
						  else soldasvacant
						  end
from nashvillehousing

update nashvillehousing
set soldasvacant = case when soldasvacant = 'Y' then 'Yes'
				   when soldasvacant = 'N' then 'No'
				   else soldasvacant
				   end

--remove duplicates
with rownumCTE as (
select *,
	ROW_NUMBER() over (
	partition by parcelID,
				 propertyAddress,
				 saleprice,
				 saledate,
				 legalreference
				 order by 
					uniqueID
	) row_num
from nashvillehousing
)
delete from rownumCTE
where row_num > 1


with rownumCTE as (
select *,
	ROW_NUMBER() over (
	partition by parcelID,
				 propertyAddress,
				 saleprice,
				 saledate,
				 legalreference
				 order by 
					uniqueID
	) row_num
from nashvillehousing
)
select * from rownumCTE
where row_num > 1


--delete unused columns
select * 
from nashvillehousing

alter table nashvillehousing
drop column owneraddress, taxdistrict, propertyaddress

alter table nashvillehousing
drop column saledate