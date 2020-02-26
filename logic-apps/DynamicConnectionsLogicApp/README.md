# Dynamic Connections with Logic Apps

This Visual Studio solution demonstrates how to use [Azure Resource Manager templates](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/) to deploy a Logic App that can write a file to 1 of 2 different storage accounts, selecting it based on the name provided in the HTTP Trigger body.

## Azure Resources

The following resources will be deployed using the included template:

- 2 x [Azure Storage Accounts](https://docs.microsoft.com/en-us/azure/storage/index)
- 2 x API Connections
- 1 x [Logic App](https://docs.microsoft.com/en-us/azure/logic-apps/index)

## Deployment

You can deploy the template using [Visual Studio](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/create-visual-studio-deployment-project) or directly in the Azure Portal using a [Custom Template Deployment](https://docs.microsoft.com/en-us/azure/azure-resource-manager/templates/deploy-portal#deploy-resources-from-custom-template).

## Testing

After deploying the template, you should see in the Outputs section the endpoint to call for the Logic App to execute.

This can be called using any HTTP Client, like Postman, to perform a POST request and you need to provide a JSON object like the following:

```json
{ "connectionName": "<NAME>" }
```

The NAME should be either **azureblob1** or **azureblob2** which match the connection names defined for the Logic App.
