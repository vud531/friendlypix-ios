//
//  Copyright (c) 2017 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Firebase
import Lightbox
import MaterialComponents.MaterialCollections

class FPAccountViewController: MDCCollectionViewController {

  var profile: FPUser!
  var headerView: FPCollectionReusableView!
  let uid = Auth.auth().currentUser!.uid
  let ref = Database.database().reference()
  var postIds: [String: Any]?
  var postSnapshots = [DataSnapshot]()
  var loadingPostCount = 0

  override func viewDidLoad() {
    super.viewDidLoad()
    self.styler.cellStyle = .card
    self.styler.cellLayoutType = .grid
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    cleanCollectionView()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    loadData()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    loadingPostCount = 0
    postSnapshots = [DataSnapshot]()
  }

  override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                               at indexPath: IndexPath) -> UICollectionReusableView {
    if kind == UICollectionElementKindSectionHeader,
      let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionElementKindSectionHeader,
                                                                       withReuseIdentifier: "HeaderView",
                                                                       for: indexPath) as? FPCollectionReusableView {
      self.headerView = headerView
      navigationItem.title = profile.fullname
      if profile.userID == uid {
        headerView.followLabel.text = "Enable notifications"
      }
      headerView.profilePictureImageView.sd_setImage(with: profile.profilePictureURL, completed: nil)
      return headerView
    }
    return UICollectionReusableView()

  }

  @objc override func collectionView(_ collectionView: UICollectionView,
                                     layout  collectionViewLayout: UICollectionViewLayout,
                                     referenceSizeForHeaderInSection section: Int) -> CGSize {
    let size = CGSize(width: collectionView.frame.size.width, height: 112)
    return size
  }

  @IBAction func didTapProfile(_ sender: Any) {
    let lightboxImages: [LightboxImage] = postSnapshots.flatMap {
      guard let value = $0.value as? [String:Any], let fullURL = (value["full_url"] as? String).flatMap(URL.init) else { return nil }
      return LightboxImage(imageURL: fullURL, text: "\(profile.fullname): \(value["text"] ?? "")")
    }

    let lightbox = LightboxController(images: lightboxImages)
    lightbox.dynamicBackground = true
    self.present(lightbox, animated: true, completion: nil)
  }

  @IBAction func valueChanged(_ sender: Any) {
    if profile.userID == uid {
      let notificationEnabled = ref.child("people").child(profile.userID).child("notificationEnabled")
      if headerView.followSwitch.isOn {
        notificationEnabled.setValue(true)
      } else {
        notificationEnabled.removeValue()
      }
      return
    }

    toggleFollow(headerView.followSwitch.isOn)
  }

  func loadData() {
    ref.child("people").child(profile.userID).observeSingleEvent(of: .value, with: { userSnapshot in
      let followingCount = userSnapshot.childSnapshot(forPath: "following").childrenCount
      self.headerView.followingLabel.text = "\(followingCount)"

      if self.profile.userID == self.uid {
        let notificationEnabled = userSnapshot.childSnapshot(forPath: "notificationEnabled")
        self.headerView.followSwitch.isOn = notificationEnabled.exists() && (notificationEnabled.value as? Bool)!
      }

      if let posts = userSnapshot.childSnapshot(forPath: "posts").value as? [String: Any] {
        self.postIds = posts
        let postCount = posts.count
        self.headerView.postsLabel.text = "\(postCount)"
        self.loadFeed()
      }
    })
    ref.child("followers").child(profile.userID).observeSingleEvent(of: .value, with: { snapshot in
      if let followers = snapshot.value as? [String: Any] {
        let followersCount = followers.count
        self.headerView.followersLabel.text = "\(followersCount)"
        if self.profile.userID != self.uid {

        // check if the currentUser is following this user
        self.headerView.followSwitch.isOn = followers[self.uid] != nil ? true : false
        }
      }
    })
  }

  override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell,
                               forItemAt indexPath: IndexPath) {
    if indexPath.item == (loadingPostCount - 3) {
      loadFeed()
    }
  }

  func loadFeed() {
    loadingPostCount += 10
    self.collectionView?.performBatchUpdates({
      for _ in 1...10 {
        if let postId = self.postIds?.popFirst()?.key {
          self.ref.child("posts/" + (postId)).observe(.value, with: { postSnapshot in
            self.postSnapshots.append(postSnapshot)
            self.collectionView?.insertItems(at: [IndexPath(item: self.postSnapshots.count - 1, section: 0)])
          })
        } else {
          break
        }
      }
    }, completion: nil)
  }

  override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    return postSnapshots.count
  }

  override func collectionView(_ collectionView: UICollectionView,
                               cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
    let postSnapshot = postSnapshots[indexPath.item]
    if let value = postSnapshot.value as? [String: Any],
      let photoUrl = value["thumb_url"] as? String {
        let imageView = UIImageView()
        cell.backgroundView = imageView
        imageView.sd_setImage(with: URL(string: photoUrl), completed: nil)
    }
    return cell
  }

  func toggleFollow(_ follow: Bool) {
    let myFeed = "feed/\(uid)/"
    ref.child("people/\(profile.userID)/posts").observeSingleEvent(of: .value, with: { snapshot in
      var lastPostID: Any = true
      var updateData = [String: Any]()
      if let posts = snapshot.value as? [String: Any] {
        // Add/remove followed user's posts to the home feed.
        for postId in posts.keys {
          updateData[myFeed + postId] = follow ? true : NSNull()
          lastPostID = postId
        }

        // Add/remove followed user to the 'following' list.
        updateData["people/\(self.uid)/following/\(self.profile.userID)"] = follow ? lastPostID : NSNull()

        // Add/remove signed-in user to the list of followers.
        updateData["followers/\(self.profile.userID)/\(self.uid)"] = follow ? true : NSNull()
        self.ref.updateChildValues(updateData) { error, _ in
          if let error = error {
            print(error.localizedDescription)
          }
        }
      }
    })
  }

  override func collectionView(_ collectionView: UICollectionView, cellHeightAt indexPath: IndexPath) -> CGFloat {
    return MDCCeil(((self.collectionView?.bounds.width)! - 14) * 0.325)
  }

  override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    performSegue(withIdentifier: "detail", sender: postSnapshots[indexPath.item])
  }

  func backButtonAction(_ sender: Any) {
    navigationController?.popViewController(animated: true)
  }

  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    if segue.identifier == "detail" {
      if let detailViewController = segue.destination as? FPPostDetailViewController,
        let sender = sender as? DataSnapshot {
        detailViewController.postSnapshot = sender
      }
    }
  }
}
