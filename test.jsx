const users = [
  { name: "Олена", age: 25 },
  { name: "Михайло", age: 30 },
  { name: "Софія", age: 22 },
];

function UserList() {
  return (
    <ul>
      {users.map((user) => (
        <li key={user.name}>
          Ім'я: {user.name}, Вік: {user.age}
        </li>
      ))}
    </ul>
  );
}

export default UserList;
