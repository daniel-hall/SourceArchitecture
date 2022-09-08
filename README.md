# SourceArchitecture

An incredibly streamlined framework for building reactive, highly-testable and scalable iOS apps. SourceArchitecture has a minimal footprint for use with new or existing code, and allows you to power screens built using UIKit or SwiftUI using exactly the same data sources.



## What's Different About Source Architecture?

- **Model-defined API instead of Protocol-defined API**

  Most architectural patterns rely on protocols to define what data and behaviors (API) will be available to client code. This is a perfectly workable approach, but it adds quite a bit of overhead in terms of creating the protocol and multiple conforming types. For example:

  ```swift
  protocol AuthenticationProvider {
    var isAuthenticated: Bool { get }
    var authToken: String? { get }
    var authError: Error? { get }
    func logInWithCredentials(_ credentials: Credentials)
    func logOut()
  }
  
  class AuthenticationManager: AuthenticationProvider {
    var isAuthenticated: Bool
    var authToken: String?
    var authError: Error?
    func logInWithCredentials(_ credentials: Credentials) {
       // Add implementation
    }
  
    func logOut() {
       // Add implementation
    }
  }
  
  class MockAuthenticationManager: AuthenticationProvider {
    var isAuthenticated: Bool
    var authToken: String?
    var authError: Error?
    func logInWithCredentials(_ credentials: Credentials) {
       // Add mock implementation
    }
  
    func logOut() {
       // Add mock implementation
    }
  }
  ```

  Protocol-based APIs like this can also run the risk of retain cycles, if for example the provider also retains the view.

  

  In contrast, SourceArchitecture defines all API in the Model types themselves. Models are structs or enums which contain both data and Actions. In contrast to the above protocol based appraoch, SourceArchitecture would expose the API like this:

  ```swift
  struct AuthenticationModel {
    let isAuthenticated: Bool
    let authToken: String?
    let authError: Error?
    let logInWithCredentials: Action<Credentials>
    let logOut: Action<Void>
  }
  ```

  Now, anything, regardless of protocol conformance can provide an instance or stream of these Models populated with the appropriate data and Actions. For example, in a test scenario instead of implementating a `MockAuthenticationManager` and conforming it to the AuthenticationProvider protocol, we can simply do this:

  ```swift
  let loginAction = Action<Credentials> { loginExpectation.fulfill() }
  let logOutAction = Action<Void> { XCTFail("logOut should not have been called") }
  let mockAuthenticationModel = AuthenticationModel(isAuthenticated: false, 
                                                    authToken: nil,
                                                    authError: nil,
                                                    logInWithCredentials: loginAction,
                                                    logOut: logOutAction)
  testSubject = .init(authModel: mockAuthenticationModel)
  ```

  No need for the overhead of creating protocols and conforming types, etc. Instead you can write less code and simpler code.

  Beyond saving extraneous code, the Model-defined approach allows for much better APIs which are self-documenting and require fewer tests. And many of these APIs are simply not possible with the protocol-defined approach. For example, in our AuthenticationProvider protocol above, there are implict rules that aren't clear to client developers. 

  - The `logOut()` method should only be called if `isAuthenticated == true`, otherwise it doesn't make sense
  - The `logInWithCredential()` method should only be called if `isAuthenticated == false`
  - The `authToken` property must ***always*** be `nil` if `isAuthenticated == false` and must ***never*** be nil if `isAuthenticated == true`
  - The `authError` property must ***always*** be `nil` if `isAuthenticated == true`


  All of these implicit rules must be implemented in every type conforming to the protocol, with defensive coding to check for the correct conditions. There also need to be extra unit tests written for every bullet point above.

  If only there were a way to make these rules explicit and guaranteed using the type system... and in Swift of course there is a way! Here is a **much** better way of modeling the API and the approach that SourceArchitecture was designed to support:
  ```swift
  enum AuthenticationModel {
    case notAuthenticated(NotAuthenticated)
    case authenticated(Authenticated)
    
    struct NotAuthenticated {
      let authError: Error?
      let logInWithCredentials: Action<Credentials>
    }
    
    struct Authenticated {
      let authToken: String
      let logOut: Action<Void>
    }
  }
  ```

  Notice that now the type system itself guarantees explicitly the four rules we stated above. The `logIn` and `logOut` actions can only be called in the right state and don't even exist in the wrong state. The `authToken` only exists in an `.authenticated` state and doesn't exist at all in the `.notAuthenticated` state. 

  

  By modeling the API this way, what have we improved?

  - Self-documenting because now developers can see clearly what properties are available when and when each action is allowed to be called. In fact, it's not even _possible_ to accidentally call the wrong thing at the wrong time since autocomplete won't suggest it and the compiler won't accept it.

  - Eliminated the need to write defensive code to ensure that the write actions are only called at the right time

  - Eliminated the need to write at least 4 unit tests

  - As a bonus, we were able to remove optionality from the `authToken` property and don't need a separate `isAuthenticated` optional property anymore since that information is carried by the case itself. Less optionality means less decision paths that developers to have to solve for!

    

  In SourceArchitecture, everything is set up to make it easy to write and use Model-defined API while providing guarantees that Actions from previous states can't be saved and called later in the wrong state and ensuring that Actions are created and executed by the same Source that owns the data.
  

- **Every Source is a simple state machine**

  In SourceArchitecture, the basic unit of logic is a Source. A Source is the single source of truth for a piece of information and controls all modifications and transactions (saving, fetching, etc.) related to that information. As we saw above, our Models can have multiple states, with different Actions available in each state which are capable of transitioning the Model to a new state (like from `.notAuthenticated` to `.authenticated`)

  Source Architecture simplifies this greatly and saves a lot of boilerplace code involved in setting up such state machines. In order to implement a Source that manages the `AuthenticationModel` state we described above, it's as simple as:

  ```swift
  final class AuthManager: SourceOf<AuthenticationModel> {
    @Action(AuthManager.logIn) var logInAction // Connect Action to private method
    @Action(AuthManager.logOut) var logOutAction // Connect Action to private method
  
    // Specifiying an intial value for the model is the single CustomSource requirement
    lazy var initialModel: AuthenticationModel 
    		= .notAuthenticated(.init(error: nil, logInWithCredentials: logInAction))
  
    private func logOut() {
       model = .notAuthenticated(.init(error: nil, logInWithCredentials: logInAction))
    }
  
    private func logIn(_ credentials: Credentials) {
      // Send credentials to API and wait for response
      switch result {
      case .success(let token):
        model = .authenticated(.init(authToken: reponse.authToken, logOut: logOutAction))
      case .failure(let error)
        model = .notAuthenticated(.init(error: error, logInWithCredentials: logInAction))  
      }
    }
  }
  ```


  Now, any observer can get the current value of the AuthenticationModel, or get a stream of updated Models that are sent whenever the state changes:

  ```swift
  // We always erase the concrete type and just reference a Source of the Model
  let authSource: Source<AuthenticationModel> = AuthManager().eraseToSource
  
  // Get the the current value of the AuthenticationModel
  let currentModel = authSource.model
  
  // Subscribe to stream of Model changes
  authSource.subscribe(self, method: Self.handleAuthChange)
  func handleAuthChange(_ model: AuthenticationModel) {
    // This method will get called every time the model changes, with the latest value
  }
  ```

  

- **UIKit works just like SwiftUI and is powered by the exact same Sources of data**

  In SourceArchitecture, anything which should present updating data to the user (whether a UIViewController, a SwiftUI View, a UITableViewCell, etc.) simply conforms to the `Renderer` protocol. This protocol only requires that the view have an @Source property named "model" with the type of the Model the view wants to display (analagous to "view model" or "view state"). For SwiftUI Views, that's the only requirement, for non-SwiftUI views there must also be a method named `render()` which will be called automatically when the model is updated.

  Here is a simplified SwiftUI View which shows the status of a coworker, using SourceArchitecture:

  ```swift
  struct CoworkerStatus {
      let name: String
      let avatar: UIImage
      let isOnline: Bool
      let statusMessage: String
  }
  
  // Note the SourceArchitecture Renderer protocol
  struct StatusView: View, Renderer {
    // The Render protocol requires this property using the @Source property wrapper
  	@Source model: CoworkerStatus
  
    var body: some View {
      VStack {
        HStack {
          Circle().foregroundColor(model.isOnline ? .green : .red)
          Image(model.avatar)
          Text(model.name)
        }
        Text(model.statusMessage)
    }
  }
  ```

  and here is a simplified example of a similar screen implemented as a UIViewController from a Storyboard:
  ```swift
  struct CoworkerStatus {
      let name: String
      let avatar: UIImage
      let isOnline: Bool
      let statusMessage: String
  }
  
  // Note the Renderer protocol again
  final class StatusView: UIVIewController, Renderer { 
    @IBOutlet private var image: UIImageView!
    @IBOutlet private var indicator: UIView!
    @IBOutlet private var name: UILabel!
    @IBOutlet private var statusMessage: UILabel!
  
    // Note that this is the same property wrapper used for both SwiftUI and UIKit
    @Source var model: CoworkerStatus
  
    // The method is required by the Renderer protocol and will be called automatically every time the Source updates the value of its CoworkerStatus model
    func render() {
      image.image = model.avatar
      indicator.backgroundColor = model.isOnline ? .green : .red
      name.text = model.name
      statusMessage.text = model.statusMessage
    }
  }
  ```


  As you can see, both UIKit and SwiftUI work the same simple way to implement the Renderer protocol and have a reactive live updating view:

  - Add a `@Source` property named `model` with the type your view will render. This should almost always be passed into your view from outside (initializer injected) rather than created internally, to allow for pulling data from APIs, testing, etc.
  - For non-SwiftUI views create a `render()` method that updates the UI with values from the model. This method will be called automatically every time the model updates. For SwiftUI, the `body` property already fulfills this role and there is no need to implement a separate `render()` method.


  It's also important to note that the ***same*** Source of CoworkerStatus can be injected into both the UIKit and SwiftUI views and power them both the same way.

- **Powerful set of built-in Models and Sources, but easy to extend and build your own reusable elements as well**

- **Composable business logic**

- **Extremely easy to test**

  

## Quick Start



## Frequently Asked Questions:



## Next Steps:





