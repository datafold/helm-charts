# Troubleshooting Google Ingress

Setting up Google Ingress from within the kubernetes cluster is quite complicated.

When setting up an internal load balancer:

* With ingress API as we use, FrontEndConfig is not compatible, but you can set SSL policy manually.
* You cannot set a backend security policy (CloudArmor)
* You cannot use managed certificates (since they can't be validated in the Google way)

When you create a certificate manually for the cluster to use, you need to make sure
it's available in the same region. Don't use a global certificate, because this cannot
be found.
