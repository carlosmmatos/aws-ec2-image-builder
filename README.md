<p align="center">
   <img src="https://raw.githubusercontent.com/CrowdStrike/falconpy/main/docs/asset/cs-logo.png" alt="CrowdStrike logo" width="500"/>
</p>

# AWS EC2 Image Builder Component for CrowdStrike Falcon Sensor

> [!IMPORTANT]
> This is currently a work in progress and is not yet available in the AWS Marketplace. Please check back soon for updates.

This repository contains an AWS EC2 Image Builder component for Linux that installs and configures the CrowdStrike Falcon sensor, preparing it as a master/golden image for your AWS environment.

The component automates the installation of the CrowdStrike Falcon sensor on an EC2 instance during the image building process. It's designed to be the final step in your image pipeline to ensure proper configuration and prevent interference from system reboots.

## Prerequisites

Before using this component, ensure the following requirements are met:

1. **API Credentials**: Store your CrowdStrike API credentials securely in either AWS Secrets Manager or AWS Systems Manager Parameter Store as SecretStrings.

> [!TIP]
> For more information on generating API keys and storing them securely, see [API Credentials](#api-credentials) below.

2. **IAM Permissions**: The IAM role used for the Image pipeline must have the necessary IAM permissions to access the stored credentials.

## API Credentials

The component uses the CrowdStrike API to download the sensor onto the target instance. It is highly recommended that you create a dedicated API client for the this component.

### Generate API Keys

1. In the CrowdStrike console, navigate to **Support and resources** > **API Clients & Keys**. Click **Add new API Client**.
2. Add the following API scopes:

    | Scope                      | Permission | Description                                                                   |
    | -------------------------- | ---------- | ----------------------------------------------------------------------------- |
    | **Installation Tokens**    | *READ*     | Allows the component to pull installation tokens from the CrowdStrike API.    |
    | **Sensor Download**        | *READ*     | Allows the component to download the sensor from the CrowdStrike API.         |
    | **Sensor update policies** | *READ*     | Allows the component to read sensor update policies from the CrowdStrike API. |

3. Click **Add** to create the API client. The next screen will display the API **CLIENT ID**, **SECRET**, and **BASE URL**. You will need all three for the next step.

    ![api-client-keys](./assets/api-client-keys.png)

> [!NOTE]
> This page is only shown once. Make sure you copy **CLIENT ID**, **SECRET**, and **BASE URL** to a secure location.

### Base URL Mapping

The CrowdStrike API base URL is determined by the region where your CrowdStrike tenant is hosted. Use the following table to map the CrowdStrike API base URL to the Cloud Region to be used by the component:

| BASE URL                                 | CLOUD REGION |
| ---------------------------------------- | ------------ |
| `https://api.crowdstrike.com`            | **us-1**     |
| `https://api.us-2.crowdstrike.com`       | **us-2**     |
| `https://api.eu-1.crowdstrike.com`       | **eu-1**     |
| `https://api.laggar.gcw.crowdstrike.com` | **us-gov-1** |

### Store API Credentials

Store the CrowdStrike API credentials in AWS Secrets Manager or AWS Systems Manager Parameter Store as SecretStrings. The component will use these credentials to authenticate with the CrowdStrike API.

<details><summary>Using AWS Secrets Manager</summary>

To use Secrets Manager as your secret backend, you must enter `SecretsManager` as the value for the `SecretStorageMethod` parameter when using the component.

Use the following as an example to create a secret with the following key/value pairs:

| Key          | Value                                                            | *Example*                        |
| ------------ | ---------------------------------------------------------------- | -------------------------------- |
| ClientId     | The **CLIENT ID** from [Generate API Keys](#generate-api-keys).  | 123456789abcdefg                 |
| ClientSecret | The **SECRET** from [Generate API Keys](#generate-api-keys).     | 123456789abcdefg123456789abcdefg |
| Cloud        | The **CLOUD REGION** from [Base URL Mapping](#base-url-mapping). | us-2                             |

You can use any secret name you like, as long as you pass in the secret name when using the component.

> [!IMPORTANT]
> The keys must match the table above.

</details>

<details><summary>Using AWS Parameter Store</summary>

To use Parameter Store as your secret backend, you must enter `ParameterStore` as the value for the `SecretStorageMethod` parameter when using component.

Use the following as an example to create the parameters in Parameter Store:

| Default Parameter Name           | Parameter Value                                                  | Parameter Type | *Example*                        |
| -------------------------------- | ---------------------------------------------------------------- | -------------- | -------------------------------- |
| /CrowdStrike/Falcon/ClientId     | The **CLIENT ID** from [Generate API Keys](#generate-api-keys).  | SecureString   | 123456789abcdefg                 |
| /CrowdStrike/Falcon/ClientSecret | The **SECRET** from [Generate API Keys](#generate-api-keys).     | SecureString   | 123456789abcdefg123456789abcdefg |
| /CrowdStrike/Falcon/Cloud        | The **CLOUD REGION** from [Base URL Mapping](#base-url-mapping). | SecureString   | us-2                             |

> [!NOTE]
> You can use any parameter name you like, as long as you pass in the correct names for the SSM Parameters in the component.

</details>

## Installation

TBD - Marketplace link/instructions

To use this component in your EC2 Image Builder pipeline:

1. Add this component as the final step in your image recipe.

> [!IMPORTANT]
> Adding this component as the last step in your image recipe ensures that the sensor doesn't generate a new AID prior to shutdown.

## Usage

The component will automatically execute during the image build process. It performs the following actions:

### Build Phase

1. Retrieves the CrowdStrike API credentials from the specified secret store.

> [!NOTE]
> Due to a current limitation in EC2 Image Builder where the AWS CLI is not guaranteed to be pre-installed, this component includes a step to verify and install the AWS CLI if needed. This extra verification is required to ensure we can securely retrieve the credentials.

2. Downloads and installs the CrowdStrike Falcon sensor.

3. Configures the sensor for use as a master/golden image.

### Validate Phase

1. Ensures the AID is absent from the sensor prior to shutdown.

### Test Phase

1. Ensures the AID is present after a test instance is spun up.

## Configuration

Modify the component's configuration file to specify:

- The secret ARN or parameter name containing the API credentials.
- The desired CrowdStrike Falcon sensor version.
- Any additional configuration parameters required for your environment.

## Troubleshooting

If you encounter issues:

1. Check the EC2 Image Builder logs for detailed error messages.
2. Verify that the instance profile has the correct IAM permissions.
3. Ensure the API credentials are correctly stored and accessible.

## Contributing

Contributions to improve the component are welcome. Please follow these steps:

1. Fork the repository.
2. Create a new branch for your feature or bug fix.
3. Submit a pull request with a clear description of your changes.

## License

This project is licensed under the [MIT License](LICENSE).

## Support

For support, please consult the [SUPPORT.md](SUPPORT.md) file.
