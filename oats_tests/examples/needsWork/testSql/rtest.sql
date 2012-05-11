-- Campaign:
update BusinessUser set bu_password=password('TestCampaignPassword') where bu_email='TestCampaignUser' order by bu_email ;


-- Admin
update BusinessUser set bu_password=password('TestAdminPassword') where bu_email='TestAdminUser' order by bu_email ;
