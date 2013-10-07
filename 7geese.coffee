chalk = require('chalk')
program = require('commander')
inquirer = require('inquirer')
request = require('request')
fs = require('fs')
_ = require('underscore')


module.exports = ->

    # Variables
    success = chalk.bold.green
    error = chalk.bold.red
    app =
        config:
            baseUrl: 'https://www.7geese.com'
            oauth: null
        oauth: null


    # Helpers Function
    getFormattedValue = (value, type) ->
        if type == 1
            value + '%'
        else if type == 2
            '$' + value
        else if type == 4
            value + '€'
        else if type == 5
            value + '¥'
        else if type == 6
            value + '£'
        else
            value


    # Welcome Message
    console.log chalk.bold.bgGreen("=== Welcome to the 7Geese command line utility ===")
    console.log "\n"


    # Initial
    keyresults = (val) -> return val.split(',')
    program
        .version('0.0.1')
        .option('-m, --message <n>', 'Add a message')
        .option('-o, --objective <n>', 'Add an objective id', parseInt)
        .option('-k, --keyresults <items>', 'Add a key result value id:value,id:value', keyresults)
        .parse(process.argv)


    # Connect User
    connectedUser = (callback) ->
        fs.readFile('./config.json', 'utf-8', (err, data) ->
            try
                data = JSON.parse(data)
            catch e
                data = {}
            if not data.config?
                inquirer.prompt([
                    type: 'input'
                    name: 'client_id'
                    message: "Please enter the client id of your 7geese application:"
                ,
                    type: 'input'
                    name: 'client_secret'
                    message: "Please enter the client secret of your 7geese application:"
                ], (answers) ->
                    app.config.oauth.client_id = answers.client_id
                    app.config.oauth.client_secret = answers.client_secret
                    fs.writeFileSync("./config.json", JSON.stringify(app))
                    connectTo7GeeseOauth( ->
                        callback()
                    )
                )
            else if err || not data.oauth?.access_token?
                console.log "User does not have any configuration file."
                connectTo7GeeseOauth( ->
                    callback()
                )
            else
                app.oauth = data.oauth
                callback()
        )


    # Connect to OAuth2
    connectTo7GeeseOauth = (callback) ->
        inquirer.prompt([
            type: 'input'
            name: 'email'
            message: "Please enter your email:"
        ,
            type: 'password'
            name: 'password'
            message: "Please enter your password:"

        ], (answers) ->
            url = "#{app.config.baseUrl}/oauth2/access_token/"
            data =
                grant_type: 'password'
                client_id: app.config.oauth.client_id
                client_secret: app.config.oauth.client_secret
                username: answers.email
                password: answers.password
                scope: 'all'
            request.post(url, {form: data}, (error, response, body) ->
                if !error
                    app.oauth = JSON.parse(body)
                    fs.writeFileSync("./config.json", JSON.stringify(app))
                    callback() if callback?
                else
                    console.log error("\nError: The email or password seems wrong, please try again.")
            )
        )


    # Load Objectives
    loadObjectives = ->
        request("#{app.config.baseUrl}/api/v1/objectives/?closed=false&limit=0&oauth_consumer_key=#{app.oauth.access_token}", (error, response, body) ->
            if !error
                data = JSON.parse(body)
                selectObjective(data.objects)
            else
                console.log chalk.bold.red("Error: Can not load your objectives.")
        )
        console.log "Loading your objectives..."


    # Select Objectives Question
    selectObjective = (objectives) ->
        data = _.filter(objectives, (objective) -> objective.participant_type == 1)
        console.log "\n"
        inquirer.prompt([
            type: 'list'
            name: 'objective'
            message: "Select an objective:"
            choices: _.map(data, (objective) -> name: objective.name, value: objective.id)
        ], (answers) ->
            inputKeyresultValues(answers.objective)
        )


    # Input Key result values
    inputKeyresultValues = (id) ->
        request("#{app.config.baseUrl}/api/v1/objectivekeyresults/?objective=#{id}&oauth_consumer_key=#{app.oauth.access_token}", (error, response, body) ->
            if !error
                data = JSON.parse(body)
                questions = _.map(data.objects, (kr) ->
                    type: 'input'
                    name: kr.resource_uri
                    default: kr.current_value
                    message: "Update the progress of the key result: \"#{kr.name}\" (#{getFormattedValue(kr.current_value, kr.measurement_type)}/#{getFormattedValue(kr.target_value, kr.measurement_type)})"
                )
                inquirer.prompt(questions, (answers) ->
                    getCheckinMessage(id, answers)
                )
            else
                console.log chalk.bold.red("Error: Can not load your objectives.")
        )


    # Get Checkin Message
    getCheckinMessage = (id, keyresults) ->
        inquirer.prompt([
            name: 'message'
            type: 'input'
            message: 'Enter a check-in message:'
        ], (answers) ->
            saveCheckin(id, keyresults, answers.message)
        )


    # Save Checkin
    saveCheckin = (id, keyresults, message) ->
        krs = []
        _.each(keyresults, (kr, i) ->
            key = i.split('/')[4]
            krs.push("#{key}:#{kr}")
        )
        k = krs.join(',')
        console.log "\nExecuting command: 7geese --objective #{id} --message \"#{message}\" --keyresults \"#{k}\"\n"
        request(
            url: "#{app.config.baseUrl}/api/v1/objectives/#{id}/checkins/?oauth_consumer_key=#{app.oauth.access_token}"
            method: 'post'
            json: true
            body:
                tagged_users: null
                key_results: _.map(keyresults, (kr, i) -> resource_uri: i, current_value: parseInt(kr, 10))
                message: message
        , (error, response, body) ->
            if !error
                console.log success("Your check-in has been saved.")
            else
                console.log chalk.bold.red("Error: Can not save your checkin.")
        )


    # Has Config
    connectedUser( ->
        if program.objective and program.message
            krs = {}
            _.each(program.keyresults, (kr) -> krs["/api/v1/objectivekeyresults/#{kr.split(':')[0]}/"] = kr.split(':')[1])
            saveCheckin(program.objective, krs, program.message)
        else
            loadObjectives()
    )
