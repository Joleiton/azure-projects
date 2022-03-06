######################################################################################################
#v1.0.4
#Created by joleiton

#  Based on https://docs.microsoft.com/en-us/azure/api-management/api-management-howto-integrate-internal-vnet-appgateway#--steps-required-for-integrating-api-management-and-application-gateway

    #Create a resource group for Resource Manager.
    #Create a Virtual Network, subnet, and public IP for the Application Gateway. Create another subnet for API Management.
    #Create an API Management service inside the VNET subnet created above and ensure you use the Internal mode.
    #Set up a custom domain name in the API Management service.
    #Create an Application Gateway configuration object.
    #Create an Application Gateway resource.
    #Create a CNAME from the public DNS name of the Application Gateway to the API Management proxy hostname.

######################################################################################################

#GLOBAL VARIABLES

#SUB
$_subscriptionId = "57acb41a-7c5f-4082-8ca9-738ab1a9a85f"

#RG
$_rgname = "rg-appgw-apim_a1v50"
$_location = "East Us"

##APIM

#1######
#apim/service

$_apimServiceName = "apiminternala1v50"  # API Management service instance name   
$_apimOrganization = "Microsoft"
$_apimAdminEmail = "joleiton@microsoft.com"

#apim/hostname
$_apim_gatewayHostname =  "api.apissec.com"
$_apim_portalHostname = "portal.apissec.com"
$_apim_managementHostname = "management.apissec.com"


#Self Signed Cert Password
$_gatewayCertPfxPassword = "123456"
$_PortalCertPfxPassword = "123456"
$_ManagementCertPfxPassword = "123456"

#######

#APPGW
$_appgwname = "appgw_a1v50"


######################################################################################################
#1  Create a Resource Group for Resource Manager 

#Step1 - Login to Azure 

#Connect-AzAccount

#Step2 - Select target subscription Id 

$subscriptionId = $_subscriptionId

Get-AzSubscription -Subscriptionid $subscriptionId | Select-AzSubscription


#Step3 - Create Resource Group in target subscription id

$resourceGroupName =  $_rgname

$location = $_location

New-AzResourceGroup -Name $resourceGroupName -Location $location


#Azure Resource Manager requires that all resource groups specify a location. 
#This is used as the default location for resources in that resource group. 
#Make sure that all commands to create an application gateway use the same resource group.

######################################################################################################
#2 Create a Virtual Network and a subnet for the application gateway & APIM 

######################################################################################################
#2 Create a Virtual Network and a subnet for the application gateway & APIM 

##################

#NSG rules for APIM Subnet 

#inbound
$inrule1 = New-AzNetworkSecurityRuleConfig -Name 'Client-APIM' -Description "Client communication to API Management" -Access Allow -Protocol Tcp -Direction Inbound -Priority 105 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix VirtualNetwork -DestinationPortRange 80,443
$inrule2 = New-AzNetworkSecurityRuleConfig -Name 'RP' -Description "Management endpoint for Azure portal and PowerShell" -Access Allow -Protocol Tcp -Direction Inbound -Priority 110 -SourceAddressPrefix ApiManagement -SourcePortRange * -DestinationAddressPrefix VirtualNetwork -DestinationPortRange 3443
$inrule3 = New-AzNetworkSecurityRuleConfig -Name 'In-Redis' -Description "Access Redis Service for Cache policies between machines" -Access Allow -Protocol Tcp -Direction Inbound -Priority 115 -SourceAddressPrefix VirtualNetwork -SourcePortRange * -DestinationAddressPrefix VirtualNetwork -DestinationPortRange 6381,6383
$inrule4 = New-AzNetworkSecurityRuleConfig -Name 'In-Rate_Limit_Counters' -Description "Sync Counters for Rate Limit policies between machines" -Access Allow -Protocol Udp -Direction Inbound -Priority 120 -SourceAddressPrefix VirtualNetwork -SourcePortRange * -DestinationAddressPrefix VirtualNetwork -DestinationPortRange 4290
$inrule5 = New-AzNetworkSecurityRuleConfig -Name 'Azure_Load_Balancer' -Description "Azure Infrastructure Load Balancer" -Access Allow -Protocol Tcp -Direction Inbound -Priority 125 -SourceAddressPrefix AzureLoadBalancer -SourcePortRange * -DestinationAddressPrefix VirtualNetwork -DestinationPortRange *
$inrule104 = New-AzNetworkSecurityRuleConfig -Name 'CASG-Rule-104' -Description "CSS Governance Security Rule.  Deny risky inbound.  https://aka.ms/casg" -Access Deny -Protocol Tcp -Direction Inbound -Priority 4096 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 13,17,19,22,23,53,69,111,119,123,135,137,138,139,161,162,389,445,512,514,593,636,873,1433,1434,1900,2049,2301,2381,3268,3306,3389,4333,5353,5432,5800,5900,5985,5986,6379,7000,7001,7199,9042,9160,9300,11211,16379,26379,27017

#outbund

$outrule1 = New-AzNetworkSecurityRuleConfig -Name 'APIM-Storage' -Description "Dependency on Azure Storage" -Access Allow -Protocol Tcp -Direction Outbound -Priority 105 -SourceAddressPrefix VirtualNetwork -SourcePortRange * -DestinationAddressPrefix Storage -DestinationPortRange 443
$outrule2 = New-AzNetworkSecurityRuleConfig -Name 'Active_Directory' -Description "Azure Active Directory (where applicable)" -Access Allow -Protocol Tcp -Direction Outbound -Priority 110 -SourceAddressPrefix VirtualNetwork -SourcePortRange * -DestinationAddressPrefix AzureActiveDirectory -DestinationPortRange 443
$outrule3 = New-AzNetworkSecurityRuleConfig -Name 'SQL' -Description "Access to Azure SQL endpoints" -Access Allow -Protocol Tcp -Direction Outbound -Priority 115 -SourceAddressPrefix VirtualNetwork -SourcePortRange * -DestinationAddressPrefix Sql -DestinationPortRange 1433
$outrule4 = New-AzNetworkSecurityRuleConfig -Name 'EventHub' -Description "Dependency for Log to Event Hub policy and monitoring agent" -Access Allow -Protocol Tcp -Direction Outbound -Priority 125 -SourceAddressPrefix VirtualNetwork -SourcePortRange * -DestinationAddressPrefix EventHub -DestinationPortRange 5671,5672,443
$outrule5 = New-AzNetworkSecurityRuleConfig -Name 'GIT' -Description "Dependency on Azure File Share for GIT" -Access Allow -Protocol Tcp -Direction Outbound -Priority 130 -SourceAddressPrefix VirtualNetwork -SourcePortRange * -DestinationAddressPrefix Storage -DestinationPortRange 445
$outrule6 = New-AzNetworkSecurityRuleConfig -Name 'AzureCloud' -Description "Health and Monitoring Extension" -Access Allow -Protocol Tcp -Direction Outbound -Priority 135 -SourceAddressPrefix VirtualNetwork -SourcePortRange * -DestinationAddressPrefix AzureCloud -DestinationPortRange 443,1200
$outrule7 = New-AzNetworkSecurityRuleConfig -Name 'AzureMonitor' -Description "Publish Diagnostics Logs and Metrics, Resource Health and Application Insights" -Access Allow -Protocol Tcp -Direction Outbound -Priority 140 -SourceAddressPrefix VirtualNetwork -SourcePortRange * -DestinationAddressPrefix AzureCloud -DestinationPortRange 443,1200
$outrule8 = New-AzNetworkSecurityRuleConfig -Name 'Internet_SMTP' -Description "Connect to SMTP Relay for sending e-mails" -Access Allow -Protocol Tcp -Direction Outbound -Priority 145 -SourceAddressPrefix VirtualNetwork -SourcePortRange * -DestinationAddressPrefix Internet -DestinationPortRange 25,587,25028
$outrule9 = New-AzNetworkSecurityRuleConfig -Name 'Out_Redis' -Description "Access Redis Service for Cache policies between machines" -Access Allow -Protocol Tcp -Direction Outbound -Priority 150 -SourceAddressPrefix VirtualNetwork -SourcePortRange * -DestinationAddressPrefix VirtualNetwork -DestinationPortRange 6381,6383
$outrule10 = New-AzNetworkSecurityRuleConfig -Name 'Out_Rate_Limit_Counters' -Description "Sync Counters for Rate Limit policies between machines" -Access Allow -Protocol Udp -Direction Outbound -Priority 155 -SourceAddressPrefix VirtualNetwork -SourcePortRange * -DestinationAddressPrefix VirtualNetwork -DestinationPortRange 4290

$nsg_apim = New-AzNetworkSecurityGroup -ResourceGroupName $_rgname -Location $_location -Name "apim_nsg" -SecurityRules $inrule1,$inrule2,$inrule3,$inrule4,$inrule5,$inrule104,$outrule1,$outrule2,$outrule3,$outrule4,$outrule5,$outrule6,$outrule7,$outrule8,$outrule9,$outrule10


################

##################

#NSG rules for APIM Subnet 

#inbound
$inrule1 = New-AzNetworkSecurityRuleConfig -Name 'Any' -Description "Any communication" -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange *
$inrule104 = New-AzNetworkSecurityRuleConfig -Name 'CASG-Rule-104' -Description "CSS Governance Security Rule.  Deny risky inbound.  https://aka.ms/casg" -Access Deny -Protocol Tcp -Direction Inbound -Priority 4096 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 13,17,19,22,23,53,69,111,119,123,135,137,138,139,161,162,389,445,512,514,593,636,873,1433,1434,1900,2049,2301,2381,3268,3306,3389,4333,5353,5432,5800,5900,5985,5986,6379,7000,7001,7199,9042,9160,9300,11211,16379,26379,27017
##

#outbund

##

$nsg_appgw = New-AzNetworkSecurityGroup -ResourceGroupName $_rgname -Location $_location -Name "appgw_nsg" -SecurityRules $inrule1,$inrule104

################

#The following example shows how to create a Virtual Network using Resource Manager.

#Step 1 - Assing the address range 10.0.0.0/24 to the subnet variable to be used for Application Gateway while creating a Virtual Network
$appgatewaysubnet = New-AzVirtualNetworkSubnetConfig -Name "subnet-appgw" -AddressPrefix "10.0.0.0/24"  -NetworkSecurityGroup $nsg_appgw

#Step 2 - Assing the address range 10.0.0.0/24 to the subnet variable to be used for API Management while creating a Virtual Network
$apimsubnet = New-AzVirtualNetworkSubnetConfig -Name "subnet-apim-1" -AddressPrefix "10.0.1.0/24"  -NetworkSecurityGroup $nsg_apim


#Step 3 - Create a Virtual Network named ****  in resource group for the RG region.  Using prefix 10.0.0.0/16 with subnets 10.0.0.0/24 and 10.0.1.0/24

$vnet = New-AzVirtualNetwork -Name "appgw-apim-vnet" -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix "10.0.0.0/16" -Subnet $appgatewaysubnet,$apimsubnet

#Step 4 - Assign a subnet variable for the next steps 

#Assign a subnet variable for the next steps

$appgatewaysubnetdata = $vnet.Subnets[0]
$apimsubnetdata = $vnet.Subnets[1]


######################################################################################################
#3 Create an API Management service inside a VNET configured in internal mode 

#Step 1 - Create an API Management Virtual Network object using the subnet $apimsubnetdata created above
$apimVirtualNetwork = New-AzApiManagementVirtualNetwork -SubnetResourceId $apimsubnetdata.Id

#Step 2 - Create an API Management service inside the Virtual Network 

$apimServiceName = $_apimServiceName # API Management service instance name 

$apimOrganization = $_apimOrganization

$apimAdminEmail = $_apimAdminEmail

$apimService = New-AzApiManagement -ResourceGroupName $resourceGroupName -Location $location -Name $apimServiceName -Organization $apimOrganization -AdminEmail $apimAdminEmail -VirtualNetwork $apimVirtualNetwork -VpnType "Internal" -Sku "Developer"

#After the above command succeeds refer to DNS Configuration required to access internal VNET API Management service to access it. This step may take more than half an hour.
#https://docs.microsoft.com/en-us/azure/api-management/api-management-using-with-internal-vnet#apim-dns-configuration

######################################################################################################


#4 - Set-up a custom domain name in API Management 

#Imnportant -- -- - -The new developer portal also requires enabling connectivity to the API Management's management endpoint in addition to the steps below.

$gatewayHostname = $_apim_gatewayHostname
$portalHostname = $_apim_portalHostname
$managementHostname = $_apim_managementHostname
#### Self Signed Certificates



####

$gatewayCertCerPath = Get-ChildItem -Path root.cer


$gatewayCertPfxPath = Get-ChildItem -Path proxy.pfx 
$portalCertPfxPath =  Get-ChildItem -Path portal.pfx 
$managementCertPfxPath = Get-ChildItem -Path management.pfx 

$gatewayCertPfxPassword = $_gatewayCertPfxPassword
$PortalCertPfxPassword = $_PortalCertPfxPassword
$ManagementCertPfxPassword  = $_ManagementCertPfxPassword


$certPwd = ConvertTo-SecureString -String $gatewayCertPfxPassword -AsPlainText -Force
$certPortalPwd = ConvertTo-SecureString -String $portalCertPfxPassword -AsPlainText -Force
$certManagementPwd = ConvertTo-SecureString -String $ManagementCertPfxPassword -AsPlainText -Force

#STEP 2 - Create and set the hostname configuration object for the proxy and for the portal


$proxyHostnameConfig =  New-AzApiManagementCustomHostnameConfiguration -Hostname $gatewayHostname -HostnameType Proxy -PfxPath $gatewayCertPfxPath -PfxPassword $certPwd

$portalHostnameConfig = New-AzApiManagementCustomHostnameConfiguration -Hostname $portalHostname -HostnameType DeveloperPortal -PfxPath $portalCertPfxPath -PfxPassword $certPortalPwd 

$managementHostnameConfig = New-AzApiManagementCustomHostnameConfiguration -Hostname $managementHostname -HostnameType Management -PfxPath $managementCertPfxPath -PfxPassword $certManagementPwd

$apimService.ProxyCustomHostnameConfiguration = $proxyHostnameConfig
$apimService.PortalCustomHostnameConfiguration = $portalHostnameConfig
$apimService.ManagementCustomHostnameConfiguration = $managementHostnameConfig

Set-AzApiManagement -InputObject $apimService


######################################################################################################

#5 - Create a public IP address for the front end configuration 

#Create  a public IP publicIP01 resource in the resource group

$publicIp2 = New-AzPublicIpAddress -Name "publicIP01" -ResourceGroupName $resourceGroupName -AllocationMethod Static  -Location $location -Sku Standard

# An IP address is assigned to the application gateway when the service starts


######################################################################################################
#6  - Create application gateway configuration

#Step 1- Create an application gateway IP configuration named gatewayIP01. When Application Gateway starts, it picks up an IP address from the subnet configured and route 
#network traffic to the IP addresses in the backend pool. Keep in mind that each instance takes one IP address

$gipcongif = New-AzApplicationGatewayIPConfiguration -Name "gatewayIP01" -Subnet $appgatewaysubnetdata 

#Step 2- Configure the front-end IP port for the public IP endpoint. This port is the port that end users connect to.

$fp01 = New-AzApplicationGatewayFrontendPort -Name "port01" -Port 443


#Step 3

#Configure the front-end IP with public IP endpoint

$fipconfig01 = New-AzApplicationGatewayFrontendIPConfig -Name "frontend1" -PublicIPAddress $publicIp2


#Step 4 -- Configure the certificates for the Application Gateway , which will be used to decrypt and re-encrypt the traffic passing through

$cert = New-AzApplicationGatewaySslCertificate -Name "certProxy01" -CertificateFile $gatewayCertPfxPath -Password $certPwd

$certPortal = New-AzApplicationGatewaySslCertificate -Name "certPortal01" -CertificateFile $portalCertPfxPath -Password $certPortalPwd

$certManagement = New-AzApplicationGatewaySslCertificate -Name "certManagement01" -CertificateFile $managementCertPfxPath -Password $certManagementPwd


 
#Step 5-  Create the HTTP listeners for the Application Gateway . Assign the front-end IP configuration , port , and TLS/SSL certificates to them.

$listener  =  New-AzApplicationGatewayHttpListener -Name "listener01" -Protocol "Https" -FrontendIPConfiguration $fipconfig01 -FrontendPort $fp01 -SslCertificate $cert -HostName $gatewayHostname -RequireServerNameIndication true 


$portalListener = New-AzApplicationGatewayHttpListener -Name "listener02" -Protocol "Https" -FrontendIPConfiguration $fipconfig01 -FrontendPort $fp01 -SslCertificate $certPortal -HostName $portalHostname -RequireServerNameIndication true


$managementListener = New-AzApplicationGatewayHttpListener -Name "listener03" -Protocol "Https" -FrontendIPConfiguration $fipconfig01 -FrontendPort $fp01 -SslCertificate $certManagement -HostName $managementHostname -RequireServerNameIndication true


#Step 6 - Create custom probes to the API Management service ContosoApi proxy domain endpoint. The path /status-0123456789abcdef is a  default health endpoint hosted on all the 
#the API Management services . Set api.contoso.net as a custom probe hostname to secure it with the TLS/SSL certificate 

$apimprobe = New-AzApplicationGatewayProbeConfig -Name "apimproxyprobe" -Protocol "Https" -HostName $gatewayHostname -Path "/status-0123456789abcdef" -Interval 30 -Timeout 120 -UnhealthyThreshold 8

$apimPortalProbe = New-AzApplicationGatewayProbeConfig -Name "apimportalprobe" -Protocol "Https" -HostName $portalHostname -Path "/signin" -Interval 60 -Timeout 300 -UnhealthyThreshold 8

$apimManagementProbe = New-AzApplicationGatewayProbeConfig -Name "apimmanagementprobe" -Protocol "Https" -HostName $managementHostname -Path "/ServiceStatus" -Interval 60 -Timeout 300 -UnhealthyThreshold 8
#Step 7 - Upload the certificate to be used on the TLS -enabled backend pool resourcesl. This is the same certificate you provided in Step 4 

$trustcert = New-AzApplicationGatewayTrustedRootCertificate -Name "trustedrootcert" -CertificateFile $gatewayCertCerPath


#Step 8 -  Configure HTTP backend settings for the Application Gateway . This includes a setting a timeout limit for backend request. After which they are cancelled. This value is different
# from the probe time out.

$apimPoolSetting = New-AzApplicationGatewayBackendHttpSettings -Name "apimPoolSetting" -Port 443 -Protocol "Https" -CookieBasedAffinity "Disabled" -Probe $apimprobe -TrustedRootCertificate $trustcert -RequestTimeout 180 -HostName $gatewayHostname 

$apimPoolPortalSetting = New-AzApplicationGatewayBackendHttpSettings -Name "apimPoolPortalSetting" -Port 443 -Protocol "Https" -CookieBasedAffinity "Disabled" -Probe $apimPortalProbe -TrustedRootCertificate $trustcert -RequestTimeout 180   -HostName $portalHostname 

$apimPoolManagementSetting = New-AzApplicationGatewayBackendHttpSettings -Name "apimPoolManagementSetting" -Port 3443 -Protocol "Https" -CookieBasedAffinity "Disabled" -Probe $apimManagementProbe -TrustedRootCertificate $trustcert  -RequestTimeout 180   -HostName $managementHostname 

#Step 9 - Configure a backend IP address pool name apimbackend with the internal virtual IP address of the APIM service created above

$apimProxyBackendPool = New-AzApplicationGatewayBackendAddresspool -Name "apimbackend" -BackendIPAddresses $apimService.PrivateIPAddresses[0] 

#Step 10  - Create rules for the Application Gateway to use basic routing 

$rule01 = New-AzApplicationGatewayRequestRoutingRule -Name "rule1" -RuleType Basic -HttpListener $listener -BackendAddressPool $apimProxyBackendPool -BackendHttpSettings $apimPoolSetting

$rule02 = New-AzApplicationGatewayRequestRoutingRule -Name "rule2" -RuleType Basic -HttpListener $portalListener -BackendAddressPool $apimProxyBackendPool -BackendHttpSettings $apimPoolPortalSetting

$rule03 = New-AzApplicationGatewayRequestRoutingRule -Name "rule3" -RuleType Basic -HttpListener $managementListener -BackendAddressPool $apimProxyBackendPool -BackendHttpSettings $apimPoolManagementSetting

#tip : change the -RuleType and routing to restric the accesss to certain pages of the developer Portal 

#Step 11 - Configure the number of instances and size for the applciation gateway . In this example , we are using the WAF SKU for increased security of the APIM 

$sku = New-AzApplicationGatewaySku -Name "WAF_v2" -Tier "WAF_v2" -Capacity 2


#Step 12 -Configure WAF to be in Preventio mode 
 
$config = New-AzapplicationGatewayWebApplicationFirewallConfiguration -Enabled $true -FirewallMode Prevention

######################################################################################################
#7  - Create Application Gateway

$appgwName = $_appgwname

$appgw = New-AzApplicationGateway -Name $appgwName -ResourceGroupName $resourceGroupName -Location $location -BackendAddressPools $apimProxyBackendPool -BackendHttpSettingsCollection $apimPoolSetting, $apimPoolPortalSetting, $apimPoolManagementSetting -FrontendIPConfigurations $fipconfig01  -GatewayIPConfigurations $gipcongif -FrontendPorts $fp01 -HttpListeners $listener,$portalListener,$managementListener -RequestRoutingRules $rule01,$rule02,$rule03  -Sku $sku -WebApplicationFirewallConfiguration $config -SslCertificates $cert , $certPortal,$certManagement -TrustedRootCertificate $trustcert -Probes $apimprobe,$apimPortalProbe,$apimManagementProbe 

$appgw
######################################################################################################

