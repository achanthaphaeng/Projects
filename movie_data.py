#!/usr/bin/env python
# coding: utf-8

# In[1]:


#import libraries
import pandas as pd
import seaborn as sns
import numpy as np
import matplotlib
import matplotlib.pyplot as plt
plt.style.use('ggplot')
from matplotlib.pyplot import figure
get_ipython().run_line_magic('matplotlib', 'inline')
matplotlib.rcParams['figure.figsize'] = (12,8) #adjusts configuration of the plots created

#read in data
df = pd.read_csv(r'C:\Users\achan\Downloads\archive\movies.csv')


# In[2]:


#look at data
df.head()


# In[3]:


#check for missing data
for col in df.columns:
    pct_missing = np.mean(df[col].isnull())
    print('{} - {}%'.format(col,pct_missing))


# In[4]:


#data types for columns
df.dtypes


# In[5]:


#change datatype of columns
df['budget'] = df['budget'].astype('int64')
df['gross'] = df['gross'].astype('int64')


# In[6]:


df.dtypes


# In[7]:


df.head()


# In[8]:


#create correct year column
df['yearcorrect'] = df['released'].astype(str).str[:4]
df.head()


# In[9]:


df = df.sort_values(by=['gross'], inplace = False, ascending = False)


# In[10]:


#look at all data
pd.set_option('display.max_rows', None)


# In[11]:


#remove duplicates
df.head().drop_duplicates()


# In[12]:


df.head()


# In[13]:


#assumption: budget has high correlation, company has high correlation with gross revenue
#build scatterplot with budget and gross revenue
plt.scatter(x = df['budget'], y = df['gross'])
plt.title('Budget vs. Gross Earning')
plt.xlabel('Gross Earning')
plt.ylabel('Budget for Film')
plt.show()


# In[14]:


df.head()


# In[15]:


#plot the budget vs gross regression w/ seaborn
sns.regplot(x = 'budget', y = 'gross', data = df, scatter_kws = {"color":"red"}, line_kws = {"color":"blue"})


# In[16]:


#correlation
df.corr(method='pearson') #correlation types: pearson (default), kendall, spearman


# In[17]:


#high correlation b/w budget and gross
correlation_matrix =  df.corr(method='pearson')
sns.heatmap(correlation_matrix, annot=True)
plt.title('Correlation Matrix for Numeric Features')
plt.xlabel('Movie Features')
plt.ylabel('Movie Features')
plt.show()


# In[18]:


#company vs gross
df.head()


# In[19]:


df_numerize = df
for col_name in df_numerize.columns:
    if (df_numerize[col_name].dtype == 'object'):
        df_numerize[col_name] = df_numerize[col_name].astype('category')
        df_numerize[col_name] = df_numerize[col_name].cat.codes
df_numerize.head()


# In[20]:


df.head()


# In[21]:


correlation_matrix_new =  df_numerize.corr(method='pearson')
sns.heatmap(correlation_matrix_new, annot=True)
plt.title('Correlation Matrix for Numeric Features')
plt.xlabel('Movie Features')
plt.ylabel('Movie Features')
plt.show()


# In[22]:


df_numerize.corr()


# In[23]:


#unstack
correlation_unstack_mat = df_numerize.corr()
corr_pairs = correlation_unstack_mat.unstack()
corr_pairs


# In[24]:


sorted_pairs = corr_pairs.sort_values()
sorted_pairs


# In[25]:


high_corr = sorted_pairs[(sorted_pairs) > 0.5]
high_corr


# In[26]:


#votes and budget have high correlation to gross earning
#company has no correlation

