'use strict';

(function (document) {
  const fileSelector = document.getElementById( 'file-selector' );
  const label = fileSelector.nextElementSibling,
      labelVal = label.innerHTML;

  fileSelector.addEventListener( 'change', function( e ) {
    let fileName = e.target.value.split( '\\' ).pop();

    if (fileName) {
      label.querySelector( 'span' ).innerHTML = fileName;
    } else {
      label.innerHTML = labelVal;
    }
  });

  // Firefox bug fix
  fileSelector.addEventListener( 'focus', function(){ fileSelector.classList.add( 'has-focus' ); });
  fileSelector.addEventListener( 'blur', function(){ fileSelector.classList.remove( 'has-focus' ); });

  ///////////

  const fileLabel = fileSelector.nextElementSibling

  const payloadSelector = document.getElementById("payload")
  const estimateButton = document.getElementById('estimate-button')

  const textAreaErrorSelector = document.getElementById('request-error-selector')
  const mainErrorSelector = document.getElementById('main-error')

  const estimatedCostsSelector = document.getElementById('estimated-costs')
  const estimatedCostsDiffSelector = document.getElementById('estimates-costs-diff')

  const toDisableButton = () => {
    estimateButton.classList.add('disabled')
    estimateButton.innerHTML = 'ESTIMATING...'
  }

  const toEnableButton = () => {
    estimateButton.classList.remove('disabled')
    estimateButton.innerHTML = 'ESTIMATE'
  }


  const isValidJSONString = (string) => {
    try {
      JSON.parse(string);
    } catch (e) {
      return false
    }
    return true
  }

  const setDataIntoTag = (data) => {
    const hasHourlyAndMonthlyField = data.hasOwnProperty('hourly') && data.hasOwnProperty('monthly')

    const hasDiffHourlyAndMonthlyField =
      data.hasOwnProperty('diff_hourly') && data.hasOwnProperty('diff_monthly')

    if (hasDiffHourlyAndMonthlyField) {
      estimatedCostsDiffSelector.innerHTML = `Estimated cost difference: USD ${data.diff_hourly} per hour, or USD ${data.diff_monthly} per month.<br /><br />Total estimated costs:  USD ${data.hourly} per hour, or USD ${data.monthly} per month.`
    } else if (hasHourlyAndMonthlyField) {
      estimatedCostsSelector.innerHTML = `Estimated costs: USD ${data.hourly} per hour, or USD ${data.monthly} per month.`
    }
  }

  const clearDataFromTag = () => {
    estimatedCostsSelector.innerHTML = ''
    estimatedCostsDiffSelector.innerHTML = ''
  }

  const postData = async (data = {}) => {
    try {
      const response = await fetch('https://cost.modules.tf/?from=website', {
        method: 'POST',
        mode: 'cors',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(data)
      })
      toEnableButton()
      return response.json()
    } catch (e) {
      toEnableButton()
      mainErrorSelector.innerHTML = `Something went wrong: ${e}`
      console.warn('Something went wrong', e)
    }
  }

  fileSelector.addEventListener('change', (event) => {
    const fileReader = new FileReader();
    fileReader.onload = function (e) {
      const textFromFile = e.target.result;
      payloadSelector.value = textFromFile;
    };
    fileReader.readAsText(event.target.files[0], "UTF-8");
  })

  estimateButton.addEventListener('click', function (event) {
    event.preventDefault()

    clearDataFromTag()

    const payloadData = payloadSelector.value.replace(/\s+/g,'')

    if (!!payloadData && isValidJSONString(payloadData)) {
      toDisableButton()
      const parsedData = JSON.parse(payloadData)
      postData(parsedData).then(data => {
        if (!!data.errors) {
          const msg = data.errors[0] && data.errors[0].message
          textAreaErrorSelector.innerHTML = msg
        } else {
          fileSelector.value = ''
          payloadSelector.value = ''
          fileLabel.querySelector( 'span' ).innerHTML = 'Choose a file (json, tfstate) ...'
          textAreaErrorSelector.innerHTML = ''
          setDataIntoTag(data)
        }
      }).catch(e => {
        console.log(e)
      })
    } else {
      textAreaErrorSelector.innerHTML = 'Please choose correct JSON file or put the content in the field'
    }
  })
})(document)
